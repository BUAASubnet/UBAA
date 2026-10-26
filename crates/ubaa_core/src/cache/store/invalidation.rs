//! 本地失效只撤销关联数据和读取票据，不执行学校写入或认证。
use super::{
    CacheError, CacheResult, OfflineRepository, TransactionBehavior, load_current_control,
    require_active,
};
use crate::cache::{CacheQuery, CacheScope};
use crate::domain::ConnectionMode;

/// 已由写流程确定的本地影响范围；缺少可信资源参数时只在本领域保守扩大。
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum CacheInvalidation {
    Signin {
        date: String,
    },
    Bykc {
        course_id: i64,
    },
    LibBook {
        day: Option<String>,
        area_id: Option<String>,
    },
    Cgyy {
        site_id: Option<i32>,
        date: Option<String>,
        order_id: Option<i32>,
    },
    Ygdk {
        classify_id: i32,
    },
    Evaluation,
}
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CacheInvalidationReport {
    pub removed_entries: u64,
    pub cancelled_reads: u64,
}
impl CacheInvalidation {
    /// 沿原课堂读取的校园日期确定关联范围，不从宿主时区或展示名称推断。
    #[must_use]
    pub fn signin_today() -> Self {
        Self::Signin {
            date: crate::features::signin::shanghai_date(),
        }
    }

    fn validate(&self) -> CacheResult<()> {
        let day = |value: &str, format: &str| {
            chrono::NaiveDate::parse_from_str(value, format)
                .is_ok_and(|date| date.format(format).to_string() == value)
        };
        let valid = match self {
            Self::Signin { date } => day(date, "%Y%m%d"),
            Self::Bykc { course_id } => *course_id > 0,
            Self::LibBook { day: date, area_id } => {
                date.as_deref().is_none_or(|d| day(d, "%Y-%m-%d"))
                    && area_id
                        .as_deref()
                        .is_none_or(|id| !id.trim().is_empty() && id.len() <= 1024)
            }
            Self::Cgyy {
                site_id,
                date,
                order_id,
            } => {
                site_id.is_none_or(|id| id > 0)
                    && order_id.is_none_or(|id| id > 0)
                    && date.as_deref().is_none_or(|d| day(d, "%Y-%m-%d"))
            }
            Self::Ygdk { classify_id } => *classify_id > 0,
            Self::Evaluation => true,
        };
        if valid {
            Ok(())
        } else {
            Err(CacheError::InvalidInput)
        }
    }
    fn affects(&self, query: &CacheQuery) -> bool {
        match (self, query) {
            (Self::Signin { date }, CacheQuery::SigninToday { date: stored }) => date == stored,
            (Self::Bykc { course_id }, CacheQuery::BykcDetail { course_id: stored }) => {
                course_id == stored
            }
            (
                Self::Bykc { .. },
                CacheQuery::BykcCourses { .. }
                | CacheQuery::BykcChosen
                | CacheQuery::BykcStatistics,
            )
            | (Self::LibBook { .. }, CacheQuery::LibBookBookings { .. })
            | (Self::Cgyy { .. }, CacheQuery::CgyyOrders { .. })
            | (
                Self::Ygdk { .. },
                CacheQuery::YgdkOverview | CacheQuery::YgdkOverviewSelection { .. },
            )
            | (Self::Evaluation, CacheQuery::EvaluationCurrent) => true,
            (
                Self::LibBook { day, .. },
                CacheQuery::LibBookLibraries { day: stored }
                | CacheQuery::LibBookAreas { day: stored, .. },
            ) => day.as_ref().is_none_or(|day| day == stored),
            (Self::LibBook { area_id, .. }, CacheQuery::LibBookAreaDetail { area_id: stored }) => {
                area_id.as_ref().is_none_or(|area| area == stored)
            }
            (
                Self::LibBook { area_id, day },
                CacheQuery::LibBookSeats {
                    area_id: stored_area,
                    day: stored_day,
                    ..
                },
            ) => {
                area_id.as_ref().is_none_or(|area| area == stored_area)
                    && day.as_ref().is_none_or(|day| day == stored_day)
            }
            (Self::Cgyy { order_id, .. }, CacheQuery::CgyyDetail { order_id: stored }) => {
                order_id.is_none_or(|id| id == *stored)
            }
            (
                Self::Cgyy { site_id, date, .. },
                CacheQuery::CgyyDay {
                    site_id: stored_site,
                    date: stored_day,
                },
            ) => {
                site_id.is_none_or(|id| id == *stored_site)
                    && date.as_ref().is_none_or(|day| day == stored_day)
            }
            (
                Self::Ygdk { classify_id },
                CacheQuery::YgdkRecords {
                    classify_id: stored,
                    ..
                }
                | CacheQuery::YgdkOverviewPeriod {
                    classify_id: stored,
                    ..
                },
            ) => classify_id == stored,
            _ => false,
        }
    }
}

pub(super) fn scope_aad(key: &[u8]) -> Vec<u8> {
    [b"ubaa.cache.request.scope.v1\0".as_slice(), key].concat()
}
impl OfflineRepository {
    /// 原子失效关联范围，包括尚无旧数据的在途读取；不影响无关票据。
    ///
    /// # Errors
    /// 已退出、旧句柄、参数/密文损坏或事务失败时原数据和读取票据均保持。
    pub fn invalidate(
        &mut self,
        route: ConnectionMode,
        impact: &CacheInvalidation,
    ) -> CacheResult<CacheInvalidationReport> {
        let tx = self
            .db
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(CacheError::from)?;
        require_active(&load_current_control(
            &tx,
            &self.crypto,
            &self.account,
            self.generation,
        )?)?;
        impact.validate()?;
        let entries = read_rows(&tx, "SELECT key, body FROM entries")?;
        let requests = read_rows(&tx, "SELECT key, scope FROM requests")?;
        let mut report = CacheInvalidationReport {
            removed_entries: 0,
            cancelled_reads: 0,
        };
        for (key, body) in entries {
            // 无法读取的旧条目仍由原单条读取隔离，不妨碍其他合法范围失效。
            let Ok(record) = self.crypto.open::<StoredScope>(&body, &key) else {
                continue;
            };
            if self.crypto.index(&(&self.account, &record.scope))? != key {
                continue;
            }
            if record.scope.route == route && impact.affects(&record.scope.query) {
                tx.execute("DELETE FROM entries WHERE key=?1", [&key])
                    .map_err(CacheError::from)?;
                report.removed_entries += 1;
            }
        }
        for (key, body) in requests {
            let scope: CacheScope = self.crypto.open(&body, &scope_aad(&key))?;
            if self.crypto.index(&(&self.account, &scope))? != key {
                return Err(CacheError::Corrupt);
            }
            if scope.route == route && impact.affects(&scope.query) {
                tx.execute("DELETE FROM requests WHERE key=?1", [&key])
                    .map_err(CacheError::from)?;
                report.cancelled_reads += 1;
            }
        }
        tx.commit().map_err(CacheError::from)?;
        Ok(report)
    }
}
#[derive(serde::Deserialize)]
struct StoredScope {
    scope: CacheScope,
}
fn read_rows(db: &rusqlite::Connection, query: &str) -> CacheResult<Vec<(Vec<u8>, Vec<u8>)>> {
    let mut statement = db.prepare(query).map_err(CacheError::from)?;
    statement
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .map_err(CacheError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(CacheError::from)
}
#[cfg(test)]
mod tests;
