//! 安装级 `SQLite` 连接和迁移。

use super::{AppServiceError, AppServiceResult, bootstrap, queue, state};
use crate::{config, internal::sqlite};
use rusqlite::{Connection, OpenFlags, Transaction, TransactionBehavior};
use std::{fs::OpenOptions, io::ErrorKind, path::Path, sync::Mutex, time::Duration};

pub(super) const DATABASE_NAME: &str = "app_service.sqlite3";
const SCHEMA: u32 = 3;
const OPEN_BUSY_TIMEOUT: Duration = Duration::from_secs(1);

pub(super) struct Store(Mutex<Connection>);

impl Store {
    pub(super) fn open(config_dir: &Path, policy_version: Option<u32>) -> AppServiceResult<Self> {
        if !config_dir.is_absolute() {
            return Err(AppServiceError::StorageUnavailable);
        }
        std::fs::create_dir_all(config_dir).map_err(|_| AppServiceError::StorageUnavailable)?;
        config::validate_config_directory(config_dir, false)
            .map_err(|_| AppServiceError::StorageUnavailable)?;
        config::restrict_config_directory(config_dir)
            .map_err(|_| AppServiceError::StorageUnavailable)?;
        let path = config_dir.join(DATABASE_NAME);
        config::validate_config_target(&path).map_err(|_| AppServiceError::StorageUnavailable)?;
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        config::restrict_file_creation(&mut options);
        match options.open(&path) {
            Ok(file) => file
                .sync_all()
                .map_err(|_| AppServiceError::StorageUnavailable)?,
            Err(error) if error.kind() == ErrorKind::AlreadyExists => {}
            Err(_) => return Err(AppServiceError::StorageUnavailable),
        }
        let mut db = sqlite::open(&path, OpenFlags::SQLITE_OPEN_READ_WRITE)?;
        // 启动时允许等待另一进程完成短事务。后续学校请求仍使用常规读取时限。
        db.busy_timeout(OPEN_BUSY_TIMEOUT)?;
        sqlite::configure_private_store(&db)?;
        let tx = db.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let version: u32 = tx.pragma_query_value(None, "user_version", |row| row.get(0))?;
        match version {
            0 => {
                tx.execute_batch(state::SCHEMA)?;
                tx.execute_batch(queue::SCHEMA)?;
            }
            1..=SCHEMA => {}
            _ => return Err(AppServiceError::UnsupportedSchema),
        }
        if version < 2 {
            tx.execute_batch(
                "ALTER TABLE app_service_state ADD COLUMN last_delivery_attempt INTEGER;",
            )?;
        }
        if version < SCHEMA {
            tx.execute_batch(bootstrap::SCHEMA)?;
            tx.pragma_update(None, "user_version", SCHEMA)?;
        }
        state::StoredState::load(&tx)?;
        if let Some(version) = policy_version {
            state::require_policy(&tx, version)?;
        }
        tx.commit()?;
        db.busy_timeout(sqlite::BUSY_TIMEOUT)?;
        Ok(Self(Mutex::new(db)))
    }

    pub(super) fn read<T>(
        &self,
        operation: impl FnOnce(&Transaction<'_>) -> AppServiceResult<T>,
    ) -> AppServiceResult<T> {
        self.access(TransactionBehavior::Deferred, operation)
    }

    pub(super) fn write<T>(
        &self,
        operation: impl FnOnce(&Transaction<'_>) -> AppServiceResult<T>,
    ) -> AppServiceResult<T> {
        self.access(TransactionBehavior::Immediate, operation)
    }

    fn access<T>(
        &self,
        behavior: TransactionBehavior,
        operation: impl FnOnce(&Transaction<'_>) -> AppServiceResult<T>,
    ) -> AppServiceResult<T> {
        let mut db = self
            .0
            .lock()
            .map_err(|_| AppServiceError::StorageUnavailable)?;
        let tx = db.transaction_with_behavior(behavior)?;
        let result = operation(&tx)?;
        tx.commit()?;
        Ok(result)
    }
}
