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

/// 图书馆对一条在借记录给出的业务状态；未识别的值保持为“其他”。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LibraryLoanStatus {
    Normal,
    Soon,
    Overdue,
    Other,
}

/// 一条当前借阅记录，只包含展示、续借目标和续借条件所需的公开字段。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryLoan {
    /// 学校提供的记录标识；只在当前账号与路线内用于续借，不推断其格式。
    pub id: String,
    pub title: String,
    pub author: Option<String>,
    pub loan_date: Option<String>,
    pub due_date: Option<String>,
    /// 已续借次数；上游缺失时保持未知，不写成零。
    pub renew_times: Option<u32>,
    /// 仍可续借次数；需要借阅条件和续借上限都可用时才给出。
    pub can_renew_times: Option<u32>,
    pub status: LibraryLoanStatus,
    pub location: Option<String>,
}

/// 完整读取本次当前借阅范围，不声明历史借阅或全部馆藏。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryLoans {
    pub entries: Vec<LibraryLoan>,
    pub total: u32,
}

/// 单本续借请求，保留确认时的借阅记录供提交前复核。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryLoanRenewRequest {
    pub loan_id: String,
    pub due_date: Option<String>,
    pub renew_times: Option<u32>,
    pub can_renew_times: Option<u32>,
}

impl From<&LibraryLoan> for LibraryLoanRenewRequest {
    fn from(loan: &LibraryLoan) -> Self {
        Self {
            loan_id: loan.id.clone(),
            due_date: loan.due_date.clone(),
            renew_times: loan.renew_times,
            can_renew_times: loan.can_renew_times,
        }
    }
}

/// 学校已接受续借；最终日期与次数以随后重新读取的借阅记录为准。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryLoanRenewResult {
    pub loan_id: String,
    pub success: bool,
}
