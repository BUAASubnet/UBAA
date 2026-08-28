//! 会话文件锁与临时文件生命周期。

use std::fs::{self, File};
use std::path::{Path, PathBuf};
use std::sync::MutexGuard;

pub(crate) struct SessionFileLock<'a> {
    pub(crate) _process_guard: MutexGuard<'a, ()>,
    pub(crate) file: File,
}

impl Drop for SessionFileLock<'_> {
    fn drop(&mut self) {
        let _ = self.file.unlock();
    }
}

pub(crate) struct TemporaryFile {
    path: PathBuf,
    remove_on_drop: bool,
}

impl TemporaryFile {
    pub(crate) fn new(path: PathBuf) -> Self {
        Self {
            path,
            remove_on_drop: true,
        }
    }

    pub(crate) fn path(&self) -> &Path {
        &self.path
    }

    pub(crate) fn persisted(&mut self) {
        self.remove_on_drop = false;
    }
}

impl Drop for TemporaryFile {
    fn drop(&mut self) {
        if self.remove_on_drop {
            let _ = fs::remove_file(&self.path);
        }
    }
}
