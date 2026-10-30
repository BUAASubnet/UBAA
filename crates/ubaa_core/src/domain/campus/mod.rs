//! 门户资料、账户指标与网费流量的只读投影。

use serde::{Deserialize, Serialize};

use crate::error::UbaaError;

/// 门户的身份与学院，仅用于资料展示。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PortalProfile {
    pub identity: String,
    pub department: String,
    pub fetched_at: i64,
}

/// 保留十进制数值与上游单位，不自动换算流量基数。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CampusAmount {
    pub value: String,
    pub unit: String,
}

/// 单项读取结果。有效零值与失败分别表示。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(
    tag = "status",
    rename_all = "snake_case",
    rename_all_fields = "camelCase"
)]
pub enum CampusMetric<T> {
    Success { value: T, fetched_at: i64 },
    Failure { error: UbaaError, fetched_at: i64 },
}

/// 门户五项账户指标，任一业务失败不覆盖其他成功项。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CampusMetrics {
    pub network_balance: CampusMetric<CampusAmount>,
    pub card_balance: CampusMetric<CampusAmount>,
    pub unread_mail: CampusMetric<u64>,
    pub borrowed_books: CampusMetric<u64>,
    pub cloud_storage_remaining: CampusMetric<CampusAmount>,
}

/// 一个网络产品的流量。两项剩余均不含套餐。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NetworkProductUsage {
    pub product_name: String,
    pub used: CampusAmount,
    pub free_remaining: CampusAmount,
    pub billable_remaining: CampusAmount,
}

/// 网费首页提供的完整产品流量表。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NetworkUsage {
    pub products: Vec<NetworkProductUsage>,
    pub remaining_excludes_packages: bool,
    pub fetched_at: i64,
}
