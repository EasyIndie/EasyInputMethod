//! Bounded weak caches for immutable packaged data, not user preferences.
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::SystemTime;

use ime_pinyin::{PinyinBackend, TablePinyinBackend};
use ime_table::Table;

use crate::error::{IME_ERR_IO, IME_ERR_LOCKED, IME_ERR_PARSE};

#[derive(Clone, PartialEq, Eq)]
struct FileKey {
    path: PathBuf,
    len: u64,
    modified: SystemTime,
}
impl FileKey {
    fn read(path: &str) -> Result<Self, i32> {
        let path = std::fs::canonicalize(path).map_err(|_| IME_ERR_IO)?;
        let metadata = std::fs::metadata(&path).map_err(|_| IME_ERR_IO)?;
        Ok(Self {
            path,
            len: metadata.len(),
            modified: metadata.modified().map_err(|_| IME_ERR_IO)?,
        })
    }
}

type PinyinKey = (FileKey, Option<FileKey>);
type PinyinEntry = (PinyinKey, Weak<dyn PinyinBackend>);

#[derive(Default)]
struct Cache {
    wubi: Vec<(FileKey, Weak<Table>)>,
    pinyin: Vec<PinyinEntry>,
}
fn cache() -> &'static Mutex<Cache> {
    static CACHE: OnceLock<Mutex<Cache>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(Cache::default()))
}

pub(crate) fn wubi(path: &str) -> Result<Arc<Table>, i32> {
    let key = FileKey::read(path)?;
    let mut cache = cache().lock().map_err(|_| IME_ERR_LOCKED)?;
    cache.wubi.retain(|(_, weak)| weak.strong_count() > 0);
    if let Some(data) = cache
        .wubi
        .iter()
        .find_map(|(k, w)| (k == &key).then(|| w.upgrade()).flatten())
    {
        return Ok(data);
    }
    let text = std::fs::read_to_string(&key.path).map_err(|_| IME_ERR_IO)?;
    let data = Arc::new(Table::from_tsv(&text).map_err(|_| IME_ERR_PARSE)?);
    if cache.wubi.len() >= 4 {
        cache.wubi.remove(0);
    }
    cache.wubi.push((key, Arc::downgrade(&data)));
    Ok(data)
}

pub(crate) fn pinyin(chars: &str, words: Option<&str>) -> Result<Arc<dyn PinyinBackend>, i32> {
    let key = (FileKey::read(chars)?, words.map(FileKey::read).transpose()?);
    let mut cache = cache().lock().map_err(|_| IME_ERR_LOCKED)?;
    cache.pinyin.retain(|(_, weak)| weak.strong_count() > 0);
    if let Some(data) = cache
        .pinyin
        .iter()
        .find_map(|(k, w)| (k == &key).then(|| w.upgrade()).flatten())
    {
        return Ok(data);
    }
    let chars = std::fs::read_to_string(&key.0.path).map_err(|_| IME_ERR_IO)?;
    let words = key
        .1
        .as_ref()
        .map(|file| std::fs::read_to_string(&file.path))
        .transpose()
        .map_err(|_| IME_ERR_IO)?
        .unwrap_or_default();
    let data: Arc<dyn PinyinBackend> = Arc::new(
        TablePinyinBackend::from_tsv(&chars, &words, "内置轻量拼音").map_err(|_| IME_ERR_PARSE)?,
    );
    if cache.pinyin.len() >= 4 {
        cache.pinyin.remove(0);
    }
    cache.pinyin.push((key, Arc::downgrade(&data)));
    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tables_are_shared_and_changed_files_create_a_new_snapshot() {
        use ime_core::Engine;
        use ime_table::CodeTableEngine;
        let path =
            std::env::temp_dir().join(format!("yinghuo-shared-wubi-{}.tsv", std::process::id()));
        std::fs::write(&path, "wq\t你\t1\n").unwrap();
        let first = wubi(path.to_str().unwrap()).unwrap();
        let second = wubi(path.to_str().unwrap()).unwrap();
        assert!(Arc::ptr_eq(&first, &second));
        std::fs::write(&path, "wq\t您好\t100\n").unwrap();
        let changed = wubi(path.to_str().unwrap()).unwrap();
        assert!(!Arc::ptr_eq(&first, &changed));
        assert_eq!(
            CodeTableEngine::new_shared(first.clone(), 4)
                .convert("wq", 1)
                .candidates[0]
                .text,
            "你"
        );
        assert_eq!(
            CodeTableEngine::new_shared(changed.clone(), 4)
                .convert("wq", 1)
                .candidates[0]
                .text,
            "您好"
        );
        let weak = Arc::downgrade(&changed);
        drop(changed);
        assert!(weak.upgrade().is_none());
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn pinyin_is_shared_and_options_remain_per_engine() {
        use ime_core::{Engine, EngineOptions};
        use ime_pinyin::PinyinEngine;
        let path =
            std::env::temp_dir().join(format!("yinghuo-shared-pinyin-{}.tsv", std::process::id()));
        std::fs::write(&path, "zhong\t中\t100\n").unwrap();
        let first = pinyin(path.to_str().unwrap(), None).unwrap();
        let second = pinyin(path.to_str().unwrap(), None).unwrap();
        assert!(Arc::ptr_eq(&first, &second));
        let mut fuzzy = PinyinEngine::new_shared(first, 32);
        let exact = PinyinEngine::new_shared(second, 32);
        fuzzy.configure(&EngineOptions {
            fuzzy: true,
            auto_commit: true,
            z_wildcard: false,
        });
        assert!(!fuzzy.convert("zong", 9).candidates.is_empty());
        assert!(exact.convert("zong", 9).candidates.is_empty());
        std::fs::remove_file(path).unwrap();
    }
}
