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
type Changes = Vec<((String, String, String), Option<u32>)>;

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
    for (index, line) in data.lines().enumerate() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let invalid_line = |reason: &str| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("第{}行：{reason}", index + 1),
            )
        };
        let fields: Vec<_> = line.split('\t').collect();
        if fields.len() != 4 {
            return Err(invalid_line("须包含方案、编码、文本、词频四列"));
        }
        validate(fields[0], fields[1], fields[2])
            .map_err(|_| invalid_line("方案、编码或文本无效"))?;
        let count: u32 = fields[3]
            .parse()
            .map_err(|_| invalid_line("词频须为正整数"))?;
        if count == 0 {
            return Err(invalid_line("词频须大于零"));
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
    use std::fmt::Write as _;
    let mut data = String::with_capacity(entries.len() * 32 + 32);
    data.push_str("# lampyris-user-dictionary v1\n");
    for ((scheme, code, text), count) in entries {
        // 直写缓冲区，避免逐行 `format!` 的临时分配（TD-01）。
        let _ = writeln!(data, "{scheme}\t{code}\t{text}\t{count}");
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
    // 不在写入路径 fsync：用户词库是高频写（每次选词），原子 rename 已保证一致性；
    // 需要落盘时由 `Store::flush()`（会话结束/导出）统一 fsync（T-MVP-07）。
    let stamp = FileStamp::from_metadata(&file.metadata()?)?;
    fs::rename(&tmp, path)?;
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
    /// 写入后尚未 fsync（写入路径不 fsync，T-MVP-07）。
    dirty: bool,
}
impl Store {
    pub fn load(path: impl Into<PathBuf>) -> io::Result<Self> {
        let path = path.into();
        let (entries, stamp) = snapshot(&path)?;
        Ok(Self {
            stamp,
            path,
            entries,
            dirty: false,
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
    fn update(&mut self, change: impl FnOnce(&Entries) -> io::Result<Changes>) -> io::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let lock = self.path.with_extension("lock");
        let _file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&lock)?;
        let _guard = Guard(lock);
        self.refresh()?;
        let changes = change(&self.entries)?;
        let entries = Arc::make_mut(&mut self.entries);
        let mut undo = Vec::with_capacity(changes.len());
        for (key, value) in changes {
            let previous = if let Some(value) = value {
                entries.insert(key.clone(), value)
            } else {
                entries.remove(&key)
            };
            undo.push((key, previous));
        }
        let result = if entries.len() > MAX_ENTRIES {
            Err(invalid())
        } else {
            atomic_write(&self.path, entries)
        };
        let stamp = match result {
            Ok(stamp) => stamp,
            Err(error) => {
                for (key, previous) in undo.into_iter().rev() {
                    if let Some(value) = previous {
                        entries.insert(key, value);
                    } else {
                        entries.remove(&key);
                    }
                }
                return Err(error);
            }
        };
        self.stamp = Some(stamp.clone());
        self.dirty = true;
        // Snapshot caching is optional after a successful atomic commit.
        if let (Ok(path), Ok(mut cache)) = (fs::canonicalize(&self.path), snapshots().lock()) {
            remember(&mut cache, SnapshotKey { path, stamp }, &self.entries);
        }
        Ok(())
    }
    pub fn learn(&mut self, scheme: &str, code: &str, text: &str) -> io::Result<()> {
        validate(scheme, code, text)?;
        let key = (scheme.into(), code.into(), text.into());
        self.update(|entries| {
            let count = entries
                .get(&key)
                .copied()
                .unwrap_or_default()
                .saturating_add(1);
            Ok(vec![(key, Some(count))])
        })
    }
    /// Learn an explicit non-first Wubi choice without letting old totals lock its rank.
    /// The persisted value is a preference weight, not a typing statistic.
    pub fn learn_preferred(&mut self, code: &str, text: &str, input: &str) -> io::Result<()> {
        validate("wubi", code, text)?;
        // Wildcard queries do not describe a literal dictionary prefix.
        let prefix = if !input.is_empty() && !input.contains('z') && code.starts_with(input) {
            input
        } else {
            code
        };
        let exact = code == prefix;
        let key = ("wubi".into(), code.into(), text.into());
        self.update(|entries| {
            let group: Vec<_> = entries
                .range((String::from("wubi"), prefix.to_owned(), String::new())..)
                .take_while(|((scheme, other_code, _), _)| {
                    scheme == "wubi" && other_code.starts_with(prefix)
                })
                .filter(|((_, other_code, _), _)| (other_code == prefix) == exact)
                .collect();
            let largest = group.iter().map(|(_, value)| **value).max().unwrap_or(0);
            let divisor = if largest > u32::MAX / 2 { 2 } else { 1 };
            let normalized = |value: u32| (value / divisor).max(1);
            let leader = group
                .iter()
                .filter(|(other, _)| **other != key)
                .map(|(_, value)| normalized(**value))
                .max()
                .unwrap_or(0);
            let current = entries.get(&key).copied().map(normalized).unwrap_or(0);
            let increment = (leader / 4).saturating_add(1);
            let mut changes: Changes = if divisor == 2 {
                group
                    .into_iter()
                    .filter(|(other, _)| **other != key)
                    .map(|(other, value)| (other.clone(), Some(normalized(*value))))
                    .collect()
            } else {
                Vec::new()
            };
            changes.push((key.clone(), Some(current.saturating_add(increment))));
            Ok(changes)
        })
    }

    pub fn import(&mut self, path: &Path) -> io::Result<()> {
        let incoming = read(path).map_err(|error| {
            io::Error::new(error.kind(), format!("{}：{}", path.display(), error))
        })?;
        self.update(|entries| {
            Ok(incoming
                .into_iter()
                .map(|(key, value)| {
                    let merged = entries.get(&key).copied().unwrap_or_default().max(value);
                    (key, Some(merged))
                })
                .collect())
        })
    }
    /// Remove one exact user entry, including its learned frequency.
    pub fn remove(&mut self, scheme: &str, code: &str, text: &str) -> io::Result<()> {
        validate(scheme, code, text)?;
        let key = (scheme.into(), code.into(), text.into());
        self.update(|entries| {
            if !entries.contains_key(&key) {
                return Err(io::Error::new(io::ErrorKind::NotFound, "未找到此用户词条"));
            }
            Ok(vec![(key, None)])
        })
    }
    pub fn export(&self, path: &Path) -> io::Result<()> {
        let (current, _) = snapshot(&self.path)?;
        atomic_write(path, &current).map(|_| ())
    }

    /// 把已写入的数据 fsync 到磁盘（写入路径平时不 fsync，T-MVP-07）。
    /// 会话结束 / 导出后调用；`Drop` 也会兜底调用一次。
    pub fn flush(&mut self) -> io::Result<()> {
        if !self.dirty {
            return Ok(());
        }
        self.dirty = false;
        fs::File::open(&self.path)?.sync_all()?;
        if let Some(parent) = self.path.parent().filter(|p| !p.as_os_str().is_empty()) {
            let _ = fs::File::open(parent).and_then(|dir| dir.sync_all());
        }
        Ok(())
    }
}

impl Drop for Store {
    fn drop(&mut self) {
        let _ = self.flush();
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
    fn snapshots_refresh_atomically_and_export_latest_version() {
        let dir = std::env::temp_dir().join(format!("yinghuo-shared-user-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("user-dictionary.tsv");
        let mut first = Store::load(&path).unwrap();
        first.learn("wubi", "zz", "测试词").unwrap();
        let mut second = Store::load(&path).unwrap();
        // The four-slot global cache may evict this path during concurrent tests.
        // Data consistency, not cache residency or pointer identity, is the contract.
        assert_eq!(first.entries(), second.entries());
        first.learn("wubi", "zz", "测试词").unwrap();
        assert_ne!(first.entries(), second.entries());
        let exported = dir.join("export.tsv");
        second.export(&exported).unwrap();
        assert_eq!(read(&exported).unwrap(), *first.entries);
        second.refresh().unwrap();
        assert_eq!(first.entries(), second.entries());
        let weak = Arc::downgrade(&first.entries);
        drop(first);
        drop(second);
        assert!(weak.upgrade().is_none());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn preferred_learning_is_grouped_and_shared_across_stores() {
        let dir = unique_dir("preferred-group");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("user.tsv");
        fs::write(&path, "wubi\ta\t精确\t1000000\nwubi\tab\t历史\t1000\npinyin\tab\t拼音\t4294967295\nwubi\tb\t无关\t4294967295\n").unwrap();
        let mut first = Store::load(&path).unwrap();
        let mut second = Store::load(&path).unwrap();
        for _ in 0..2 {
            first.learn_preferred("ac", "常用", "a").unwrap();
            second.learn_preferred("ac", "常用", "a").unwrap();
        }
        first.refresh().unwrap();
        assert_eq!(
            first.entries()[&("wubi".into(), "ac".into(), "常用".into())],
            1004
        );
        assert_eq!(
            first.entries()[&("wubi".into(), "a".into(), "精确".into())],
            1000000
        );
        assert_eq!(
            first.entries()[&("pinyin".into(), "ab".into(), "拼音".into())],
            u32::MAX
        );
        assert_eq!(
            first.entries()[&("wubi".into(), "b".into(), "无关".into())],
            u32::MAX
        );
        assert_eq!(first.entries(), second.entries());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn preferred_learning_rebases_saturated_weights_without_losing_entries() {
        let dir = unique_dir("preferred-saturation");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("user.tsv");
        fs::write(
            &path,
            "wubi\tab\t历史\t4294967295\nwubi\tabc\t补全\t4294967295\n",
        )
        .unwrap();
        let mut store = Store::load(&path).unwrap();
        for _ in 0..4 {
            store.learn_preferred("ab", "常用", "ab").unwrap();
        }
        let history = store.entries()[&("wubi".into(), "ab".into(), "历史".into())];
        let preferred = store.entries()[&("wubi".into(), "ab".into(), "常用".into())];
        assert!(preferred > history);
        assert!(preferred < u32::MAX);
        assert_eq!(
            store.entries()[&("wubi".into(), "abc".into(), "补全".into())],
            u32::MAX
        );
        assert_eq!(Store::load(&path).unwrap().entries(), store.entries());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn preferred_learning_rolls_back_rebasing_when_capacity_is_full() {
        let dir = unique_dir("preferred-rollback");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("user.tsv");
        let data: String = (0..MAX_ENTRIES)
            .map(|i| format!("wubi\tab\t词{i}\t4294967295\n"))
            .collect();
        fs::write(&path, &data).unwrap();
        let mut store = Store::load(&path).unwrap();
        let before = store.entries().clone();
        assert!(store.learn_preferred("ab", "新词", "ab").is_err());
        assert_eq!(store.entries(), &before);
        assert_eq!(fs::read_to_string(&path).unwrap(), data);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn wildcard_preference_uses_only_the_selected_full_code_group() {
        let dir = unique_dir("preferred-wildcard");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("user.tsv");
        fs::write(&path, "wubi\tab\t同码\t1000\nwubi\tac\t异码\t1000000\n").unwrap();
        let mut store = Store::load(&path).unwrap();
        store.learn_preferred("ab", "目标", "az").unwrap();
        assert_eq!(
            store.entries()[&("wubi".into(), "ab".into(), "目标".into())],
            251
        );
        assert_eq!(
            store.entries()[&("wubi".into(), "ac".into(), "异码".into())],
            1000000
        );
        fs::remove_dir_all(dir).unwrap();
    }

    fn unique_dir(tag: &str) -> std::path::PathBuf {
        std::env::temp_dir().join(format!(
            "yinghuo-isolate-{tag}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ))
    }

    #[test]
    fn stale_lock_blocks_writes_preserves_data_and_manual_recovery_works() {
        let dir = unique_dir("stale-lock");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("user.tsv");
        let mut store = Store::load(&path).unwrap();
        store.learn("wubi", "ab", "词甲").unwrap();
        let before = fs::read(&path).unwrap();
        // 模拟异常退出遗留的锁文件。
        fs::write(path.with_extension("lock"), "").unwrap();
        assert!(store.learn("wubi", "ab", "词乙").is_err());
        // 原数据一字未动。
        assert_eq!(fs::read(&path).unwrap(), before);
        // 手工恢复（确认无活动写者后删除残留锁）后写入恢复正常。
        fs::remove_file(path.with_extension("lock")).unwrap();
        store.learn("wubi", "ab", "词乙").unwrap();
        assert_eq!(
            store.entries()[&("wubi".into(), "ab".into(), "词乙".into())],
            1
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn capacity_limits_are_enforced() {
        let at_limit: String = (0..MAX_ENTRIES)
            .map(|i| format!("wubi\tab\t词{i}\t1\n"))
            .collect();
        assert!(parse(&at_limit).is_ok());
        let over_limit: String = (0..=MAX_ENTRIES)
            .map(|i| format!("wubi\tab\t词{i}\t1\n"))
            .collect();
        assert!(parse(&over_limit).is_err());
    }

    #[cfg(unix)]
    #[test]
    fn read_only_directory_preserves_existing_data() {
        use std::os::unix::fs::PermissionsExt;
        let dir = unique_dir("readonly");
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("user.tsv");
        let mut store = Store::load(&path).unwrap();
        store.learn("wubi", "ab", "词甲").unwrap();
        let before = fs::read(&path).unwrap();
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o500)).unwrap();
        assert!(store.learn("wubi", "ab", "词乙").is_err());
        assert_eq!(fs::read(&path).unwrap(), before);
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).unwrap();
        fs::remove_dir_all(&dir).unwrap();
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

    #[test]
    fn failed_atomic_write_and_capacity_keep_memory_and_disk_unchanged() {
        let dir = std::env::temp_dir().join(format!(
            "lampyris-rollback-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let path = dir.join("user.tsv");
        let mut store = Store::load(&path).unwrap();
        store.learn("wubi", "ab", "原词").unwrap();
        let shared = Arc::clone(&store.entries);
        let before = fs::read(&path).unwrap();
        let collision = path.with_extension(format!("tmp-{}", std::process::id()));
        fs::write(&collision, "独立哨兵").unwrap();
        assert!(store.learn("wubi", "ab", "原词").is_err());
        assert!(store.learn("wubi", "ab", "新词").is_err());
        assert_eq!(store.entries(), shared.as_ref());
        assert_eq!(fs::read(&path).unwrap(), before);
        assert_eq!(fs::read_to_string(&collision).unwrap(), "独立哨兵");
        fs::remove_file(&collision).unwrap();
        store.learn("pinyin", "ab", "原词").unwrap();
        fs::write(&collision, "独立哨兵").unwrap();
        let before_entries = store.entries().clone();
        let before = fs::read(&path).unwrap();
        assert!(store.remove("wubi", "ab", "原词").is_err());
        assert_eq!(store.entries(), &before_entries);
        assert_eq!(fs::read(&path).unwrap(), before);
        fs::remove_file(&collision).unwrap();
        store.remove("wubi", "ab", "原词").unwrap();
        assert_eq!(store.entries().len(), 1);
        assert!(store
            .entries()
            .contains_key(&("pinyin".into(), "ab".into(), "原词".into())));
        assert_eq!(
            store.remove("wubi", "ab", "原词").unwrap_err().kind(),
            io::ErrorKind::NotFound
        );
        assert_eq!(Store::load(&path).unwrap().entries(), store.entries());
        let full: Entries = (0..MAX_ENTRIES)
            .map(|i| (("wubi".into(), "ab".into(), format!("词{i}")), 1))
            .collect();
        fs::write(&path, serialize(&full)).unwrap();
        store.reload().unwrap();
        let before = fs::read(&path).unwrap();
        assert!(store.learn("wubi", "ab", "超限新词").is_err());
        assert_eq!(store.entries(), &full);
        assert_eq!(fs::read(&path).unwrap(), before);
        store.learn("wubi", "ab", "词0").unwrap();
        assert_eq!(
            store.entries()[&("wubi".into(), "ab".into(), "词0".into())],
            2
        );
        fs::remove_dir_all(dir).unwrap();
    }
}
