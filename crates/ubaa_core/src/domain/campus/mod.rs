//! 门户资料、账户指标与网费流量的只读投影。

use serde::{Deserialize, Serialize};

use crate::error::UbaaError;

/// 门户的身份与学院；Core 使用明确身份选择学业系统。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PortalProfile {
    pub identity: String,
    pub department: String,
    pub fetched_at: i64,
}

/// 十进制数值与单位；派生流量合计按校园账户规则换算。
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

/// 一个网络产品的流量；在线免费剩余包含套餐可用流量，计费剩余保持上游值。
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

/// 充值前的卡信息；不含 openid 等凭据。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CampusRechargePreflight {
    /// 卡序号，充值下单的必填参数。
    pub idserial: String,
    /// 上游十进制余额字符串，不换算。
    pub balance: String,
    pub fetched_at: i64,
}

/// 已创建的充值订单及由用户选择支付渠道的原商户收银台。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CampusRechargeOrder {
    /// 收银台订单号，同时用于查询支付状态。
    pub orderno: String,
    /// 已验证的商户收银台地址，与本订单号一致。
    pub cashier_url: String,
    /// 下单金额，单位分，十进制字符串。
    pub amount_fen: String,
    pub fetched_at: i64,
}
