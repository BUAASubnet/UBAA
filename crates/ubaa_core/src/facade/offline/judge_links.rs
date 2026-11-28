use super::{CacheError, CachePayload, CacheQuery, CacheResult, CacheScope, OfflineCache};
use crate::cache::{CacheCompleteness, OfflineRepository};
use crate::domain::ConnectionMode;
use std::collections::BTreeSet;

fn scope(term: &str) -> CacheScope {
    CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::JudgeLinkOverrides { term: term.into() },
    }
}

fn read(
    repo: &mut OfflineRepository,
    scope: &CacheScope,
    now: i64,
) -> CacheResult<BTreeSet<String>> {
    match repo.read(scope, now) {
        Ok(Some(record)) => match record.payload {
            CachePayload::JudgeLinkOverrides { unlinked, .. } => Ok(unlinked),
            _ => Err(CacheError::Corrupt),
        },
        Ok(None) | Err(CacheError::Corrupt) => Ok(BTreeSet::new()),
        Err(error) => Err(error),
    }
}

impl OfflineCache {
    /// 读取本账号本学期取消关联的希冀课程编号。
    ///
    /// # Errors
    /// 学期无效、账号已退出或仓库不可用时返回缓存错误。
    pub fn read_judge_overrides(&self, term: &str) -> CacheResult<Vec<String>> {
        self.repository(|repo| {
            Ok(read(repo, &scope(term), chrono::Utc::now().timestamp())?
                .into_iter()
                .collect())
        })
    }

    /// 在同一本地锁中更新取消关联集合，恢复关联时移除编号。
    ///
    /// # Errors
    /// 范围无效、账号关闭或写入失败时返回缓存错误。
    pub fn set_judge_link(&self, term: &str, id: &str, linked: bool) -> CacheResult<()> {
        if id.trim().is_empty() || id.len() > 1024 {
            return Err(CacheError::InvalidInput);
        }
        self.repository(|repo| {
            let scope = scope(term);
            let now = chrono::Utc::now().timestamp();
            let mut unlinked = read(repo, &scope, now)?;
            let changed = if linked {
                unlinked.remove(id)
            } else {
                unlinked.insert(id.into())
            };
            if changed {
                let ticket = repo.begin_read(scope)?;
                repo.publish(
                    &ticket,
                    CachePayload::JudgeLinkOverrides {
                        term: term.into(),
                        unlinked,
                    },
                    now,
                    CacheCompleteness::Complete,
                )?;
            }
            Ok(())
        })
    }
}
