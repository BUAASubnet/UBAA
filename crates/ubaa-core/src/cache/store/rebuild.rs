//! 显式清理/重建当前账号库，不参与启动失败后的自动回退。
use super::{
    CacheClearReport, CacheError, CacheKey, CacheLimits, CacheResult, Crypto, Generation,
    OfflineRepository, Path, files, initialize_database, open_connection, validate_limits,
};
use rusqlite::config::DbConfig;

/// 返回此结果说明内容已清除；缺少仓库表示随后初始化/维护失败。
pub struct CacheRecovery {
    pub repository: Option<OfflineRepository>,
    pub report: CacheClearReport,
}
impl OfflineRepository {
    /// 仅在用户明确清理当前账号的业务副本后调用；不自动判断密钥是否损坏。
    ///
    /// # Errors
    /// 清空前失败返回错误；清空后失败放在报告中，不能宣称已恢复可用。
    pub fn clear_or_rebuild(
        root: &Path,
        account: &str,
        key: CacheKey,
        limits: CacheLimits,
    ) -> CacheResult<CacheRecovery> {
        Self::clear_or_rebuild_with(root, account, key, limits, initialize_database)
    }
    pub(super) fn clear_or_rebuild_with(
        root: &Path,
        account: &str,
        key: CacheKey,
        limits: CacheLimits,
        after_reset: impl FnOnce(
            &mut rusqlite::Connection,
            &Crypto,
            &str,
            CacheLimits,
        ) -> CacheResult<Generation>,
    ) -> CacheResult<CacheRecovery> {
        validate_limits(limits)?;
        let path = files::database_path(root, account)?;
        let mut db = open_connection(&path)?;
        // VACUUM提交后仍持独占锁，避免其他连接观察空库并生成另一个控制记录。
        db.execute_batch("PRAGMA locking_mode=EXCLUSIVE;")
            .map_err(CacheError::from)?;
        let crypto = Crypto::new(key);
        let account = account.to_ascii_lowercase();
        match initialize_database(&mut db, &crypto, &account, limits) {
            Ok(generation) => {
                let mut repo = Self {
                    db,
                    crypto,
                    account,
                    path,
                    limits,
                    generation,
                };
                let report = repo.clear_for_reopen()?;
                let crypto = repo.crypto;
                drop(repo.db);
                Ok(Self::finish_recovery(
                    root,
                    &repo.account,
                    crypto,
                    limits,
                    report,
                ))
            }
            Err(CacheError::Corrupt | CacheError::UnsupportedVersion) => {
                db.set_db_config(DbConfig::SQLITE_DBCONFIG_RESET_DATABASE, true)
                    .map_err(CacheError::from)?;
                let reset = db.execute_batch("VACUUM").map_err(CacheError::from);
                let disabled = db
                    .set_db_config(DbConfig::SQLITE_DBCONFIG_RESET_DATABASE, false)
                    .map_err(CacheError::from);
                reset?;
                let initialized =
                    disabled.and_then(|_| after_reset(&mut db, &crypto, &account, limits));
                drop(db);
                let report = CacheClearReport {
                    usage: None,
                    compacted: true,
                    maintenance_error: initialized.err(),
                };
                if report.maintenance_error.is_some() {
                    return Ok(CacheRecovery {
                        repository: None,
                        report,
                    });
                }
                Ok(Self::finish_recovery(
                    root, &account, crypto, limits, report,
                ))
            }
            Err(error) => Err(error),
        }
    }
    fn finish_recovery(
        root: &Path,
        account: &str,
        crypto: Crypto,
        limits: CacheLimits,
        mut report: CacheClearReport,
    ) -> CacheRecovery {
        let ready = (|| {
            let path = files::database_path(root, account)?;
            let mut db = open_connection(&path)?;
            let generation = initialize_database(&mut db, &crypto, account, limits)?;
            Ok(Self {
                db,
                crypto,
                account: account.to_owned(),
                path,
                limits,
                generation,
            })
        })();
        match ready {
            Ok(mut repository) => {
                match repository.usage() {
                    Ok(usage) => report.usage = Some(usage),
                    Err(error) => {
                        report.maintenance_error = Some(error);
                        return CacheRecovery {
                            repository: None,
                            report,
                        };
                    }
                }
                CacheRecovery {
                    repository: Some(repository),
                    report,
                }
            }
            Err(error) => {
                report.maintenance_error = Some(error);
                CacheRecovery {
                    repository: None,
                    report,
                }
            }
        }
    }
}
