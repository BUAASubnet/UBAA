use serde::{Deserialize, Serialize};

/// 写操作资格。
///
/// `Unknown` 表示当前稳定 DTO 缺少足以安全判定操作的字段；调用方必须按拒绝处理，
/// 不得把未知状态降级为允许。
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ActionEligibility {
    /// 已由 Core 根据当前读取结果确认可以发起操作。
    Allowed,
    /// 已由 Core 根据当前读取结果确认不可发起操作。
    Denied,
    /// 当前读取结果不足以作出安全判断。
    #[default]
    Unknown,
}
