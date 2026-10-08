//! 外部编辑监听：mtime 轮询 + 防抖 → `reload`。
//!
//! 优先 mtime 轮询（极简、免 `notify` 依赖树）；外部编辑等价于一次写入，
//! 解析失败时由 `ConfigStore::reload` 内部保留上一份可用快照。

use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime};

use crate::ConfigStore;

/// 文件监听句柄：`Drop` 时停止并回收后台线程。
pub struct FileWatcher {
    stop: Arc<AtomicBool>,
    handle: Option<JoinHandle<()>>,
}

impl FileWatcher {
    /// 启动后台监听线程。
    ///
    /// - `poll_interval`：检查 mtime 的周期；
    /// - `debounce`：检测到变化后等待 mtime 稳定的时长，随后执行一次 `reload`。
    pub fn start(store: Arc<ConfigStore>, poll_interval: Duration, debounce: Duration) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let stop_flag = Arc::clone(&stop);
        let handle = thread::spawn(move || {
            watch_loop(store, stop_flag, poll_interval, debounce);
        });
        Self {
            stop,
            handle: Some(handle),
        }
    }
}

impl Drop for FileWatcher {
    fn drop(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(handle) = self.handle.take() {
            let _ = handle.join();
        }
    }
}

fn mtime(path: &Path) -> Option<SystemTime> {
    fs_metadata_modified(path)
}

fn fs_metadata_modified(path: &Path) -> Option<SystemTime> {
    std::fs::metadata(path).and_then(|m| m.modified()).ok()
}

fn watch_loop(
    store: Arc<ConfigStore>,
    stop: Arc<AtomicBool>,
    poll_interval: Duration,
    debounce: Duration,
) {
    let mut last = mtime(store.path());
    let mut pending: Option<Instant> = None;

    loop {
        if stop.load(Ordering::Relaxed) {
            break;
        }
        thread::sleep(poll_interval);
        if stop.load(Ordering::Relaxed) {
            break;
        }

        let current = mtime(store.path());
        if current != last {
            last = current;
            pending = Some(Instant::now() + debounce);
        }

        if let Some(deadline) = pending {
            if Instant::now() >= deadline {
                pending = None;
                // 解析失败时 reload 内部保留上一份快照，这里忽略错误即可。
                let _ = store.reload();
            }
        }
    }
}
