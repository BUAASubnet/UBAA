//! 受限磁盘会话存储、schema 编码与文件锁。

use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use crate::domain::ConnectionMode;
use crate::error::Result;

use super::file_safety::{
    create_temporary_file, open_existing_session_file, prevent_symlink_following,
    restrict_directory, restrict_file_creation, restrict_open_file, session_error, sync_directory,
    validate_directory, validate_open_regular_file, validate_regular_file,
};
use super::ports::SessionStore;
use super::storage::{SessionFileLock, TemporaryFile};
use super::types::{
    DualSessionMutation, DualSessionSnapshot, RouteSessionSnapshot, SessionMutation,
    SessionSnapshot, VersionedDualSession, VersionedSession,
};

const MAX_SESSION_FILE_BYTES: usize = 1024 * 1024;
const REVISION_FILE_BYTES: usize = 17;

/// 使用 `<config-dir>/session.json` 的文件会话存储。
#[derive(Clone)]
pub struct FileSessionStore {
    path: PathBuf,
    process_lock: Arc<Mutex<()>>,
}

/// schema-v2 双路线会话文件的路线范围视图。
///
/// 该视图实现旧版 `SessionStore` 端口，使现有运行时保持路线局部；读取和比较交换仍针对
/// 共享的双路线文件及其单一修订锁执行。
#[derive(Clone)]
pub struct RouteSessionStore {
    inner: FileSessionStore,
    mode: ConnectionMode,
}

impl std::fmt::Debug for RouteSessionStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RouteSessionStore")
            .field("mode", &self.mode)
            .field("inner", &self.inner)
            .finish()
    }
}

impl RouteSessionStore {
    /// 基于已有双文件存储构造路线作用域存储。
    #[must_use]
    pub const fn new(inner: FileSessionStore, mode: ConnectionMode) -> Self {
        Self { inner, mode }
    }
}

impl SessionStore for RouteSessionStore {
    fn load_versioned(&self) -> Result<VersionedSession> {
        let current = self.inner.load_dual_versioned()?;
        let snapshot = current.snapshot.and_then(|dual| match self.mode {
            ConnectionMode::Direct => dual.sessions.direct,
            ConnectionMode::WebVpn => dual.sessions.webvpn,
        });
        Ok(VersionedSession {
            revision: current.revision,
            snapshot: snapshot.map(|slot| slot.into_legacy(self.mode)),
        })
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        let current = self.inner.load_dual_versioned()?;
        if current.revision != expected_revision {
            return Ok(SessionMutation::Conflict);
        }
        let mut dual = current
            .snapshot
            .unwrap_or_else(|| DualSessionSnapshot::new(None, None));
        let slot = replacement.map(RouteSessionSnapshot::from_legacy);
        match self.mode {
            ConnectionMode::Direct => dual.sessions.direct = slot,
            ConnectionMode::WebVpn => dual.sessions.webvpn = slot,
        }
        let replacement = if dual.sessions.direct.is_none() && dual.sessions.webvpn.is_none() {
            None
        } else {
            Some(&dual)
        };
        match self
            .inner
            .compare_exchange_dual(expected_revision, replacement)?
        {
            DualSessionMutation::Applied { revision } => Ok(SessionMutation::Applied { revision }),
            DualSessionMutation::Conflict => Ok(SessionMutation::Conflict),
        }
    }

    fn is_revision_current(&self, expected_revision: u64) -> Result<bool> {
        Ok(self.inner.load_dual_versioned()?.revision == expected_revision)
    }
}

impl std::fmt::Debug for FileSessionStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("FileSessionStore")
            .field("path", &"[REDACTED]")
            .finish()
    }
}

impl FileSessionStore {
    /// 创建受限的配置目录和会话路径。
    ///
    /// # Errors
    ///
    /// 当目录无法创建或设置访问限制时返回安全的持久化错误。
    pub fn new(config_dir: impl AsRef<Path>) -> Result<Self> {
        let config_dir = config_dir.as_ref();
        fs::create_dir_all(config_dir)
            .map_err(|_| session_error("could not create config directory"))?;
        validate_directory(config_dir)?;
        restrict_directory(config_dir)?;
        let store = Self {
            path: config_dir.join("session.json"),
            process_lock: Arc::new(Mutex::new(())),
        };
        drop(store.open_lock_file()?);
        Ok(store)
    }

    /// 返回用于诊断和测试的准确会话路径。
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }

    /// 在会话锁下加载 schema v2，或迁移一个旧版单路线快照。
    ///
    /// # Errors
    ///
    /// 会话文件、修订锁或序列化数据不可安全读取或迁移时返回错误。
    pub fn load_dual(&self) -> Result<Option<DualSessionSnapshot>> {
        self.load_dual_versioned().map(|current| current.snapshot)
    }

    /// 加载双路线快照及其同步版本号。
    ///
    /// # Errors
    ///
    /// 会话文件、修订锁或序列化数据不可安全读取或迁移时返回错误。
    pub fn load_dual_versioned(&self) -> Result<VersionedDualSession> {
        let mut lock = self.acquire_lock()?;
        let mut revision = read_revision(&mut lock.file)?;
        let snapshot = match self.read_body_unlocked()? {
            None => None,
            Some(body) => {
                if let Ok(snapshot) = serde_json::from_slice::<DualSessionSnapshot>(&body) {
                    if snapshot.schema_version != 2 {
                        return Err(session_error("session format is invalid"));
                    }
                    Some(snapshot)
                } else {
                    let legacy: SessionSnapshot = serde_json::from_slice(&body)
                        .map_err(|_| session_error("session format is invalid"))?;
                    let slot = RouteSessionSnapshot::from_legacy(&legacy);
                    let migrated = match legacy.mode {
                        ConnectionMode::Direct => DualSessionSnapshot::new(Some(slot), None),
                        ConnectionMode::WebVpn => DualSessionSnapshot::new(None, Some(slot)),
                    };
                    revision = revision
                        .checked_add(1)
                        .ok_or_else(|| session_error("session revision is exhausted"))?;
                    write_revision(&mut lock.file, revision)?;
                    self.save_unlocked(&encode_dual_snapshot(&migrated)?)?;
                    Some(migrated)
                }
            }
        };
        Ok(VersionedDualSession { snapshot, revision })
    }

    /// 原子持久化完整的 schema-v2 双路线快照。
    ///
    /// # Errors
    ///
    /// 无法读取、编码或原子替换会话文件时返回错误。
    pub fn save_dual(&self, snapshot: &DualSessionSnapshot) -> Result<DualSessionSnapshot> {
        loop {
            let current = self.load_dual_versioned()?;
            match self.compare_exchange_dual(current.revision, Some(snapshot))? {
                DualSessionMutation::Applied { .. } => return Ok(snapshot.clone()),
                DualSessionMutation::Conflict => {}
            }
        }
    }

    /// 持有与修订版本相同的操作系统锁时，对 schema-v2 快照执行比较交换。
    ///
    /// # Errors
    ///
    /// schema 无效或无法安全锁定、编码、写入会话文件时返回错误。
    pub fn compare_exchange_dual(
        &self,
        expected_revision: u64,
        replacement: Option<&DualSessionSnapshot>,
    ) -> Result<DualSessionMutation> {
        if replacement.is_some_and(|snapshot| snapshot.schema_version != 2) {
            return Err(session_error("session format is invalid"));
        }
        let body = replacement.map(encode_dual_snapshot).transpose()?;
        let mut lock = self.acquire_lock()?;
        let current_revision = read_revision(&mut lock.file)?;
        if current_revision != expected_revision {
            return Ok(DualSessionMutation::Conflict);
        }
        let revision = current_revision
            .checked_add(1)
            .ok_or_else(|| session_error("session revision is exhausted"))?;
        write_revision(&mut lock.file, revision)?;
        match body {
            Some(body) => self.save_unlocked(&body)?,
            None => self.clear_unlocked()?,
        }
        Ok(DualSessionMutation::Applied { revision })
    }
}

impl SessionStore for FileSessionStore {
    fn load_versioned(&self) -> Result<VersionedSession> {
        let mut lock = self.acquire_lock()?;
        Ok(VersionedSession {
            revision: read_revision(&mut lock.file)?,
            snapshot: self.load_unlocked()?,
        })
    }

    fn compare_exchange(
        &self,
        expected_revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        let body = replacement.map(encode_snapshot).transpose()?;
        let mut lock = self.acquire_lock()?;
        let current_revision = read_revision(&mut lock.file)?;
        if current_revision != expected_revision {
            return Ok(SessionMutation::Conflict);
        }
        let revision = current_revision
            .checked_add(1)
            .ok_or_else(|| session_error("session revision is exhausted"))?;
        write_revision(&mut lock.file, revision)?;
        match body {
            Some(body) => self.save_unlocked(&body)?,
            None => self.clear_unlocked()?,
        }
        Ok(SessionMutation::Applied { revision })
    }
}

impl FileSessionStore {
    fn read_body_unlocked(&self) -> Result<Option<Vec<u8>>> {
        let Some(file) = open_existing_session_file(&self.path)? else {
            return Ok(None);
        };
        restrict_open_file(&file, "could not restrict session file")?;
        let mut body = Vec::new();
        file.take(MAX_SESSION_FILE_BYTES as u64 + 1)
            .read_to_end(&mut body)
            .map_err(|_| session_error("could not read session"))?;
        if body.len() > MAX_SESSION_FILE_BYTES {
            return Err(session_error("session file exceeds the allowed size"));
        }
        Ok(Some(body))
    }

    fn load_unlocked(&self) -> Result<Option<SessionSnapshot>> {
        let Some(body) = self.read_body_unlocked()? else {
            return Ok(None);
        };
        serde_json::from_slice(&body)
            .map(Some)
            .map_err(|_| session_error("session format is invalid"))
    }

    fn save_unlocked(&self, body: &[u8]) -> Result<()> {
        validate_regular_file(&self.path, "session path is not a regular file")?;
        let parent = self
            .path
            .parent()
            .ok_or_else(|| session_error("session path has no parent directory"))?;
        let (temporary, mut file) = create_temporary_file(parent)?;
        let mut cleanup = TemporaryFile::new(temporary);
        restrict_open_file(&file, "could not restrict session file")?;
        file.write_all(body)
            .map_err(|_| session_error("could not write session"))?;
        file.flush()
            .map_err(|_| session_error("could not flush session"))?;
        file.sync_all()
            .map_err(|_| session_error("could not sync session"))?;
        drop(file);

        validate_regular_file(&self.path, "session path is not a regular file")?;
        fs::rename(cleanup.path(), &self.path)
            .map_err(|_| session_error("could not replace session"))?;
        cleanup.persisted();
        sync_directory(parent)
    }

    fn clear_unlocked(&self) -> Result<()> {
        if !validate_regular_file(&self.path, "session path is not a regular file")? {
            return Ok(());
        }
        match fs::remove_file(&self.path) {
            Ok(()) => {
                if let Some(parent) = self.path.parent() {
                    sync_directory(parent)?;
                }
                Ok(())
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(_) => Err(session_error("could not clear session")),
        }
    }

    fn lock_path(&self) -> PathBuf {
        self.path.with_file_name(".session.lock")
    }

    fn open_lock_file(&self) -> Result<File> {
        let path = self.lock_path();
        let mut options = OpenOptions::new();
        options.read(true).write(true).create(true);
        restrict_file_creation(&mut options);
        prevent_symlink_following(&mut options);
        let Ok(file) = options.open(&path) else {
            validate_regular_file(&path, "session lock path is not a regular file")?;
            return Err(session_error("could not open session lock"));
        };
        validate_open_regular_file(
            &file,
            "session lock path is not a regular file",
            "could not inspect session lock",
        )?;
        restrict_open_file(&file, "could not restrict session lock")?;
        Ok(file)
    }

    fn acquire_lock(&self) -> Result<SessionFileLock<'_>> {
        let process_guard = self
            .process_lock
            .lock()
            .map_err(|_| session_error("session process lock is unavailable"))?;
        let parent = self
            .path
            .parent()
            .ok_or_else(|| session_error("session path has no parent directory"))?;
        validate_directory(parent)?;
        let file = self.open_lock_file()?;
        file.lock()
            .map_err(|_| session_error("could not lock session"))?;
        Ok(SessionFileLock {
            _process_guard: process_guard,
            file,
        })
    }
}

fn encode_snapshot(snapshot: &SessionSnapshot) -> Result<Vec<u8>> {
    let body = serde_json::to_vec_pretty(snapshot)
        .map_err(|_| session_error("could not encode session"))?;
    if body.len() > MAX_SESSION_FILE_BYTES {
        return Err(session_error("encoded session exceeds the allowed size"));
    }
    Ok(body)
}

fn encode_dual_snapshot(snapshot: &DualSessionSnapshot) -> Result<Vec<u8>> {
    let body = serde_json::to_vec_pretty(snapshot)
        .map_err(|_| session_error("could not encode session"))?;
    if body.len() > MAX_SESSION_FILE_BYTES {
        return Err(session_error("encoded session exceeds the allowed size"));
    }
    Ok(body)
}

fn read_revision(file: &mut File) -> Result<u64> {
    file.seek(SeekFrom::Start(0))
        .map_err(|_| session_error("could not read session revision"))?;
    let mut body = Vec::new();
    file.take(REVISION_FILE_BYTES as u64 + 1)
        .read_to_end(&mut body)
        .map_err(|_| session_error("could not read session revision"))?;
    if body.is_empty() {
        return Ok(0);
    }
    if body.len() != REVISION_FILE_BYTES || body.last() != Some(&b'\n') {
        return Err(session_error("session revision format is invalid"));
    }
    let digits = std::str::from_utf8(&body[..REVISION_FILE_BYTES - 1])
        .map_err(|_| session_error("session revision format is invalid"))?;
    u64::from_str_radix(digits, 16).map_err(|_| session_error("session revision format is invalid"))
}

fn write_revision(file: &mut File, revision: u64) -> Result<()> {
    let body = format!("{revision:016x}\n");
    file.seek(SeekFrom::Start(0))
        .and_then(|_| file.write_all(body.as_bytes()))
        .and_then(|()| file.set_len(REVISION_FILE_BYTES as u64))
        .and_then(|()| file.flush())
        .and_then(|()| file.sync_all())
        .map_err(|_| session_error("could not sync session revision"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn independent_store_instances_are_serialized_by_the_session_file_lock() {
        use std::sync::mpsc;
        use std::time::Duration;

        let root = std::env::temp_dir().join(format!(
            "ubaa-independent-session-lock-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let _ = std::fs::remove_dir_all(&root);
        let store = FileSessionStore::new(&root).expect("store opens");
        let (locked_tx, locked_rx) = mpsc::channel();
        let (release_tx, release_rx) = mpsc::channel();
        let holder = store.clone();
        let holder_thread = std::thread::spawn(move || {
            let lock = holder.acquire_lock().expect("lock opens");
            locked_tx.send(()).expect("signal lock");
            release_rx.recv().expect("release signal");
            drop(lock);
        });
        locked_rx.recv().expect("lock acquired");

        let waiter = store.clone();
        let (done_tx, done_rx) = mpsc::channel();
        let waiter_thread = std::thread::spawn(move || {
            waiter.load_versioned().expect("load after lock");
            done_tx.send(()).expect("signal load");
        });
        assert!(done_rx.recv_timeout(Duration::from_millis(100)).is_err());
        release_tx.send(()).expect("release lock");
        done_rx
            .recv_timeout(Duration::from_secs(2))
            .expect("waiter proceeds after release");
        holder_thread.join().expect("holder exits");
        waiter_thread.join().expect("waiter exits");
        let _ = std::fs::remove_dir_all(root);
    }
}
