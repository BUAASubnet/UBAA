//! 财务收入的最小展示投影，不包含银行卡、证件或认证材料。
use serde::{Deserialize, Serialize};
#[derive(Clone, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceIncome {
    pub id: String,
    pub project: Option<String>,
    pub description: Option<String>,
    pub amount_cents: Option<i64>,
    pub tax_cents: Option<i64>,
    pub paid_cents: Option<i64>,
    /// 上游百分比展示值，缺失时保持未知。
    pub tax_rate: Option<String>,
    pub recorded_date: Option<String>,
    pub year: Option<String>,
    pub month: Option<String>,
}
impl std::fmt::Debug for FinanceIncome {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("FinanceIncome([已隐藏])")
    }
}
/// 完整读取本次接口返回范围，不声明银行到账或全部历史覆盖。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FinanceIncomes {
    pub entries: Vec<FinanceIncome>,
    pub total: u32,
}
