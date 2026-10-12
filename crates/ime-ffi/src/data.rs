//! Bounded weak caches for immutable packaged data, not user preferences.
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock, Weak};
use std::time::SystemTime;

use ime_pinyin::{PinyinBackend, TablePinyinBackend};
use ime_table::Table;

use crate::error::{IME_ERR_IO, IME_ERR_LOCKED, IME_ERR_PARSE};
use crate::variant::VariantMap;

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
    variant: Vec<(FileKey, Weak<VariantMap>)>,
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
    let backend =
        TablePinyinBackend::from_tsv(&chars, &words, "内置轻量拼音").map_err(|_| IME_ERR_PARSE)?;
    if !backend.has_character_data() || (key.1.is_some() && !backend.has_word_data()) {
        return Err(IME_ERR_PARSE);
    }
    let data: Arc<dyn PinyinBackend> = Arc::new(backend);
    if cache.pinyin.len() >= 4 {
        cache.pinyin.remove(0);
    }
    cache.pinyin.push((key, Arc::downgrade(&data)));
    Ok(data)
}

/// 载入（并缓存）简→繁转换表；文件不存在/不可读返回错误码。
pub(crate) fn variant(path: &str) -> Result<Arc<VariantMap>, i32> {
    let key = FileKey::read(path)?;
    let mut cache = cache().lock().map_err(|_| IME_ERR_LOCKED)?;
    cache.variant.retain(|(_, weak)| weak.strong_count() > 0);
    if let Some(data) = cache
        .variant
        .iter()
        .find_map(|(k, w)| (k == &key).then(|| w.upgrade()).flatten())
    {
        return Ok(data);
    }
    let text = std::fs::read_to_string(&key.path).map_err(|_| IME_ERR_IO)?;
    let data = Arc::new(VariantMap::from_tsv(&text).map_err(|_| IME_ERR_PARSE)?);
    if cache.variant.len() >= 4 {
        cache.variant.remove(0);
    }
    cache.variant.push((key, Arc::downgrade(&data)));
    Ok(data)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn packaged_pinyin_rejects_empty_characters_and_explicit_empty_words() {
        let root =
            std::env::temp_dir().join(format!("lampyris-pinyin-empty-{}", std::process::id()));
        std::fs::create_dir_all(&root).unwrap();
        let chars = root.join("chars.tsv");
        let words = root.join("words.tsv");
        std::fs::write(&chars, "# no data").unwrap();
        let chars_path = chars.to_str().unwrap();
        assert!(matches!(pinyin(chars_path, None), Err(IME_ERR_PARSE)));
        std::fs::write(&chars, "ni\t你\t100\n").unwrap();
        std::fs::write(&words, "# no words").unwrap();
        assert!(matches!(
            pinyin(chars_path, Some(words.to_str().unwrap())),
            Err(IME_ERR_PARSE)
        ));
        assert!(pinyin(chars_path, None).is_ok());
        std::fs::remove_dir_all(root).unwrap();
    }

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
