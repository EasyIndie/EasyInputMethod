//! Bounded, auditable user dictionary data; no configuration or network IO.
#![forbid(unsafe_code)]

use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

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

fn atomic_write(path: &Path, entries: &Entries) -> io::Result<()> {
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
    fs::rename(&tmp, path)?;
    fs::File::open(parent)?.sync_all()?;
    Ok(())
}

pub struct Store {
    path: PathBuf,
    entries: Entries,
    modified: Option<std::time::SystemTime>,
}
fn modified(path: &Path) -> Option<std::time::SystemTime> {
    fs::metadata(path).and_then(|m| m.modified()).ok()
}
impl Store {
    pub fn load(path: impl Into<PathBuf>) -> io::Result<Self> {
        let path = path.into();
        let entries = read(&path)?;
        Ok(Self {
            modified: modified(&path),
            path,
            entries,
        })
    }
    pub fn entries(&self) -> &Entries {
        &self.entries
    }
    pub fn reload(&mut self) -> io::Result<()> {
        self.entries = read(&self.path)?;
        self.modified = modified(&self.path);
        Ok(())
    }
    pub fn refresh(&mut self) -> io::Result<()> {
        if modified(&self.path) != self.modified {
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
        let mut entries = read(&self.path)?;
        change(&mut entries)?;
        if entries.len() > MAX_ENTRIES {
            return Err(invalid());
        }
        atomic_write(&self.path, &entries)?;
        self.entries = entries;
        self.modified = modified(&self.path);
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
        atomic_write(path, &self.entries)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
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
