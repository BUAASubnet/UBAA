//! 校园账户指标的逐项快照：本次失败的项保留上次成功值及其时间。
use crate::domain::{CampusAmount, CampusMetric, CampusMetrics};
use serde::{Deserialize, Serialize};

/// 一项指标最近一次成功取得的值。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CachedCampusItem<T> {
    pub value: T,
    pub fetched_at: i64,
}

/// 只保存成功值；失败不写入，也不把失败改写成零。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CachedCampusMetrics {
    pub network_balance: Option<CachedCampusItem<CampusAmount>>,
    pub card_balance: Option<CachedCampusItem<CampusAmount>>,
    pub unread_mail: Option<CachedCampusItem<u64>>,
    pub borrowed_books: Option<CachedCampusItem<u64>>,
    pub cloud_storage_remaining: Option<CachedCampusItem<CampusAmount>>,
}

fn pick<T: Clone>(
    current: &CampusMetric<T>,
    previous: Option<&CachedCampusItem<T>>,
) -> Option<CachedCampusItem<T>> {
    match current {
        CampusMetric::Success { value, fetched_at } => Some(CachedCampusItem {
            value: value.clone(),
            fetched_at: *fetched_at,
        }),
        CampusMetric::Failure { .. } => previous.cloned(),
    }
}

impl CachedCampusMetrics {
    /// 本次成功项覆盖旧值，失败项沿用上次成功值。
    #[must_use]
    pub fn merge(previous: Option<&Self>, current: &CampusMetrics) -> Self {
        Self {
            network_balance: pick(
                &current.network_balance,
                previous.and_then(|v| v.network_balance.as_ref()),
            ),
            card_balance: pick(
                &current.card_balance,
                previous.and_then(|v| v.card_balance.as_ref()),
            ),
            unread_mail: pick(
                &current.unread_mail,
                previous.and_then(|v| v.unread_mail.as_ref()),
            ),
            borrowed_books: pick(
                &current.borrowed_books,
                previous.and_then(|v| v.borrowed_books.as_ref()),
            ),
            cloud_storage_remaining: pick(
                &current.cloud_storage_remaining,
                previous.and_then(|v| v.cloud_storage_remaining.as_ref()),
            ),
        }
    }

    /// 五项均有成功值时才算完整快照。
    #[must_use]
    pub fn is_complete(&self) -> bool {
        self.network_balance.is_some()
            && self.card_balance.is_some()
            && self.unread_mail.is_some()
            && self.borrowed_books.is_some()
            && self.cloud_storage_remaining.is_some()
    }

    pub(super) fn valid(&self) -> bool {
        let amount = |item: &Option<CachedCampusItem<CampusAmount>>| {
            item.as_ref().is_none_or(|item| {
                !item.value.value.trim().is_empty() && item.value.value.len() <= 64
            })
        };
        let any = self.network_balance.is_some()
            || self.card_balance.is_some()
            || self.unread_mail.is_some()
            || self.borrowed_books.is_some()
            || self.cloud_storage_remaining.is_some();
        any && amount(&self.network_balance)
            && amount(&self.card_balance)
            && amount(&self.cloud_storage_remaining)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::{ErrorCode, ErrorKind, UbaaError};

    fn amount(value: &str) -> CampusAmount {
        CampusAmount {
            value: value.into(),
            unit: "元".into(),
        }
    }

    fn failure<T>(at: i64) -> CampusMetric<T> {
        CampusMetric::Failure {
            error: UbaaError::new(
                ErrorCode::UpstreamUnavailable,
                ErrorKind::Upstream,
                true,
                "合成失败",
            ),
            fetched_at: at,
        }
    }

    fn metrics(at: i64, fee: CampusMetric<CampusAmount>) -> CampusMetrics {
        CampusMetrics {
            network_balance: fee,
            card_balance: CampusMetric::Success {
                value: amount("0"),
                fetched_at: at,
            },
            unread_mail: CampusMetric::Success {
                value: 3,
                fetched_at: at,
            },
            borrowed_books: failure(at),
            cloud_storage_remaining: CampusMetric::Success {
                value: amount("48.6"),
                fetched_at: at,
            },
        }
    }

    #[test]
    fn 失败项沿用上次成功值且成功项更新() {
        let first = CachedCampusMetrics::merge(
            None,
            &metrics(
                10,
                CampusMetric::Success {
                    value: amount("10.66"),
                    fetched_at: 10,
                },
            ),
        );
        // 首次没有图书成功值，不能用零补齐。
        assert!(first.borrowed_books.is_none());
        assert!(!first.is_complete());
        assert!(first.valid());

        let second = CachedCampusMetrics::merge(Some(&first), &metrics(20, failure(20)));
        let fee = second.network_balance.expect("网费沿用上次值");
        assert_eq!(fee.value.value, "10.66");
        assert_eq!(fee.fetched_at, 10);
        assert_eq!(second.card_balance.expect("校园卡").fetched_at, 20);
        assert!(second.borrowed_books.is_none());
    }

    #[test]
    fn 全部缺失或空金额不是有效快照() {
        assert!(!CachedCampusMetrics::default().valid());
        let blank = CachedCampusMetrics {
            card_balance: Some(CachedCampusItem {
                value: amount(" "),
                fetched_at: 1,
            }),
            ..Default::default()
        };
        assert!(!blank.valid());
    }
}
