//! Bounded, auditable user dictionary data; no configuration or network IO.
#![forbid(unsafe_code)]

use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock, Weak};

const MAX_BYTES: u64 = 2 * 1024 * 1024;
const MAX_ENTRIES: usize = 10_000;
pub type Entries = BTreeMap<(String, String, String), u32>;

fn invalid() -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, "用户词库格式或容量无效")
}

pub fn validate(scheme: &str, code: &str, text: &str) -> io::Result<()> {
    if !matches!(scheme, "wubi" | "pinyin")
        || code.is_empty()
        || code.len() > 64
        || !code.bytes().all(|c| c.is_ascii_lowercase())
        || text.is_empty()
        || text.len() > 256
        || text.chars().any(char::is_control)
    {
        return Err(invalid());
    }
    Ok(())
}

pub fn parse(data: &str) -> io::Result<Entries> {
    if data.len() as u64 > MAX_BYTES {
        return Err(invalid());
    }
    let mut entries = Entries::new();
    for line in data
        .lines()
        .filter(|s| !s.is_empty() && !s.starts_with('#'))
    {
        let fields: Vec<_> = line.split('\t').collect();
        if fields.len() != 4 {
            return Err(invalid());
        }
        validate(fields[0], fields[1], fields[2])?;
        let count: u32 = fields[3].parse().map_err(|_| invalid())?;
        if count == 0 {
            return Err(invalid());
        }
        let key = (fields[0].into(), fields[1].into(), fields[2].into());
        entries
            .entry(key)
            .and_modify(|old: &mut u32| *old = (*old).max(count))
            .or_insert(count);
        if entries.len() > MAX_ENTRIES {
            return Err(invalid());
        }
    }
    Ok(entries)
}

fn read(path: &Path) -> io::Result<Entries> {
    let file = match fs::File::open(path) {
        Ok(file) => file,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(Entries::new()),
        Err(e) => return Err(e),
    };
    let mut data = String::new();
    file.take(MAX_BYTES + 1).read_to_string(&mut data)?;
    parse(&data)
}

fn serialize(entries: &Entries) -> String {
    let mut data = String::from("# yinghuo-user-dictionary v1\n");
    for ((scheme, code, text), count) in entries {
        data.push_str(&format!("{scheme}\t{code}\t{text}\t{count}\n"));
    }
    data
}

struct Guard(PathBuf);
impl Drop for Guard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}

fn atomic_write(path: &Path, entries: &Entries) -> io::Result<FileStamp> {
    let data = serialize(entries);
    if data.len() as u64 > MAX_BYTES {
        return Err(invalid());
    }
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or(Path::new("."));
    fs::create_dir_all(parent)?;
    let tmp = path.with_extension(format!("tmp-{}", std::process::id()));
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options.open(&tmp)?;
    let _guard = Guard(tmp.clone());
    file.write_all(data.as_bytes())?;
    file.sync_all()?;
    let stamp = FileStamp::from_metadata(&file.metadata()?)?;
    fs::rename(&tmp, path)?;
    fs::File::open(parent)?.sync_all()?;
    Ok(stamp)
}

#[derive(Clone, PartialEq, Eq)]
struct FileStamp {
    len: u64,
    modified: std::time::SystemTime,
    identity: Option<(u64, u64)>,
}
impl FileStamp {
    fn from_metadata(metadata: &fs::Metadata) -> io::Result<Self> {
        #[cfg(unix)]
        let identity = {
            use std::os::unix::fs::MetadataExt;
            Some((metadata.dev(), metadata.ino()))
        };
        #[cfg(not(unix))]
        let identity = None;
        Ok(Self {
            len: metadata.len(),
            modified: metadata.modified()?,
            identity,
        })
    }
    fn read(path: &Path) -> io::Result<Option<Self>> {
        match fs::metadata(path) {
            Ok(metadata) => Self::from_metadata(&metadata).map(Some),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error),
        }
    }
}
#[derive(Clone, PartialEq, Eq)]
struct SnapshotKey {
    path: PathBuf,
    stamp: FileStamp,
}
type SnapshotCache = Vec<(SnapshotKey, Weak<Entries>)>;
fn snapshots() -> &'static Mutex<SnapshotCache> {
    static CACHE: OnceLock<Mutex<SnapshotCache>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(Vec::new()))
}
fn remember(cache: &mut SnapshotCache, key: SnapshotKey, data: &Arc<Entries>) {
    cache.retain(|(old, weak)| old != &key && weak.strong_count() > 0);
    if cache.len() >= 4 {
        cache.remove(0);
    }
    cache.push((key, Arc::downgrade(data)));
}
fn snapshot(path: &Path) -> io::Result<(Arc<Entries>, Option<FileStamp>)> {
    let Some(stamp) = FileStamp::read(path)? else {
        return Ok((Arc::new(Entries::new()), None));
    };
    let key = SnapshotKey {
        path: fs::canonicalize(path)?,
        stamp: stamp.clone(),
    };
    let mut cache = snapshots()
        .lock()
        .map_err(|_| io::Error::other("用户词库缓存锁不可用"))?;
    cache.retain(|(_, weak)| weak.strong_count() > 0);
    if let Some(data) = cache
        .iter()
        .find_map(|(old, weak)| (old == &key).then(|| weak.upgrade()).flatten())
    {
        return Ok((data, Some(stamp)));
    }
    let data = Arc::new(read(path)?);
    remember(&mut cache, key, &data);
    Ok((data, Some(stamp)))
}

pub struct Store {
    path: PathBuf,
    entries: Arc<Entries>,
    stamp: Option<FileStamp>,
}
impl Store {
    pub fn load(path: impl Into<PathBuf>) -> io::Result<Self> {
        let path = path.into();
        let (entries, stamp) = snapshot(&path)?;
        Ok(Self {
            stamp,
            path,
            entries,
        })
    }
    pub fn entries(&self) -> &Entries {
        &self.entries
    }
    pub fn reload(&mut self) -> io::Result<()> {
        let (entries, stamp) = snapshot(&self.path)?;
        self.entries = entries;
        self.stamp = stamp;
        Ok(())
    }
    pub fn refresh(&mut self) -> io::Result<()> {
        if FileStamp::read(&self.path)? != self.stamp {
            self.reload()?;
        }
        Ok(())
    }
    fn update(&mut self, change: impl FnOnce(&mut Entries) -> io::Result<()>) -> io::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let lock = self.path.with_extension("lock");
        let _file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&lock)?;
        let _guard = Guard(lock);
        let (current, _) = snapshot(&self.path)?;
        let mut entries = (*current).clone();
        drop(current);
        change(&mut entries)?;
        if entries.len() > MAX_ENTRIES {
            return Err(invalid());
        }
        let stamp = atomic_write(&self.path, &entries)?;
        let entries = Arc::new(entries);
        let key = SnapshotKey {
            path: fs::canonicalize(&self.path)?,
            stamp: stamp.clone(),
        };
        let mut cache = snapshots()
            .lock()
            .map_err(|_| io::Error::other("用户词库缓存锁不可用"))?;
        remember(&mut cache, key, &entries);
        self.entries = entries;
        self.stamp = Some(stamp);
        Ok(())
    }
    pub fn learn(&mut self, scheme: &str, code: &str, text: &str) -> io::Result<()> {
        validate(scheme, code, text)?;
        self.update(|entries| {
            let count = entries
                .entry((scheme.into(), code.into(), text.into()))
                .or_default();
            *count = count.saturating_add(1);
            Ok(())
        })
    }
    pub fn import(&mut self, path: &Path) -> io::Result<()> {
        let incoming = read(path)?;
        self.update(|entries| {
            for (key, value) in incoming {
                entries
                    .entry(key)
                    .and_modify(|v| *v = (*v).max(value))
                    .or_insert(value);
            }
            Ok(())
        })
    }
    pub fn export(&self, path: &Path) -> io::Result<()> {
        let (current, _) = snapshot(&self.path)?;
        atomic_write(path, &current).map(|_| ())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn adversarial_corpus_is_handled_without_panicking() {
        let long_number = "9".repeat(1000);
        let cases: Vec<String> = vec![
            String::new(),
            "\n\n".into(),
            "# only comment\n".into(),
            "\u{feff}wubi\tab\t词\t1\n".into(),
            "wubi\tab\t词\t1\r\n".into(),
            "wubi\tab\t词\n".into(),
            "wubi\t\t词\t1\n".into(),
            "\tab\t词\t1\n".into(),
            "wubi\tab\t词\t0\n".into(),
            "wubi\tab\t词\t-1\n".into(),
            format!("wubi\tab\t词\t{long_number}\n"),
            "wubi\tab\t词\tx\n".into(),
            "wubi\tAB\t词\t1\n".into(),
            "wubi\tab\t🦄\t1\n".into(),
            "wubi\tab\t词\t1\t2\n".into(),
            "a".repeat(100_000),
        ];
        for case in cases {
            // 只要求“不 panic”；合法/非法由既有单测断言。
            let _ = parse(&case);
        }
    }

    #[test]
    fn snapshots_share_data_refresh_atomically_and_export_latest_version() {
        let dir = std::env::temp_dir().join(format!("yinghuo-shared-user-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("user-dictionary.tsv");
        let mut first = Store::load(&path).unwrap();
        first.learn("wubi", "zz", "测试词").unwrap();
        let mut second = Store::load(&path).unwrap();
        assert!(Arc::ptr_eq(&first.entries, &second.entries));
        first.learn("wubi", "zz", "测试词").unwrap();
        assert!(!Arc::ptr_eq(&first.entries, &second.entries));
        let exported = dir.join("export.tsv");
        second.export(&exported).unwrap();
        assert_eq!(read(&exported).unwrap(), *first.entries);
        second.refresh().unwrap();
        assert!(Arc::ptr_eq(&first.entries, &second.entries));
        let weak = Arc::downgrade(&first.entries);
        drop(first);
        drop(second);
        assert!(weak.upgrade().is_none());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn rejects_untrusted_rows() {
        for bad in [
            "wubi\tab\t词\t0",
            "wubi\tA\t词\t1",
            "x\tab\t词\t1",
            "wubi\tab\t词\0\t1",
            "wubi\tab\t词",
        ] {
            assert!(parse(bad).is_err());
        }
        assert!(parse(&"x".repeat(MAX_BYTES as usize + 1)).is_err());
    }
    #[test]
    fn persists_merges_and_preserves_good_data_on_failure() {
        let dir = std::env::temp_dir().join(format!(
            "yinghuo-dict-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let path = dir.join("user.tsv");
        let mut a = Store::load(&path).unwrap();
        let mut b = Store::load(&path).unwrap();
        a.learn("wubi", "ab", "词甲").unwrap();
        b.learn("pinyin", "ci", "词乙").unwrap();
        a.reload().unwrap();
        assert_eq!(a.entries().len(), 2);
        let export = dir.join("export.tsv");
        a.export(&export).unwrap();
        a.import(&export).unwrap();
        assert_eq!(a.entries().len(), 2);
        let before = fs::read(&path).unwrap();
        fs::write(dir.join("bad.tsv"), "invalid").unwrap();
        assert!(a.import(&dir.join("bad.tsv")).is_err());
        assert_eq!(fs::read(&path).unwrap(), before);
        fs::write(path.with_extension("lock"), "").unwrap();
        assert!(a.learn("wubi", "ab", "词甲").is_err());
        assert_eq!(fs::read(&path).unwrap(), before);
        fs::remove_file(path.with_extension("lock")).unwrap();
        a.learn("wubi", "ab", "词甲").unwrap();
        assert_eq!(
            Store::load(&path).unwrap().entries()[&("wubi".into(), "ab".into(), "词甲".into())],
            2
        );
        fs::remove_dir_all(dir).unwrap();
    }
}
