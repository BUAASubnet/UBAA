use super::{BhpanDownloadReceipt, BhpanItem, BhpanListRange};
use serde::Serialize;

/// 当前客户端签发的同一对象/非空版本快照，宿主不能构造句柄。
#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct BhpanFileVersion {
    #[serde(skip)]
    pub(crate) handle: String,
    pub docid: String,
    pub rev: String,
    pub name: String,
    pub bytes: u64,
}
/// 已读范围不足时明确保留未知，不能据此覆盖或删除远端对象。
#[derive(Clone, Debug)]
pub enum BhpanPathLookup {
    Found(BhpanItem),
    Missing {
        parent: BhpanItem,
        remaining: Vec<String>,
    },
    Unknown {
        parent: BhpanItem,
        remaining: Vec<String>,
        range: BhpanListRange,
    },
}
#[derive(Clone, Debug)]
pub struct BhpanVersionDownloadReceipt {
    pub version: BhpanFileVersion,
    pub download: BhpanDownloadReceipt,
}
/// 最终登记与结果未知分开表达，未知仍交付已经取得的同对象/U，用于只读核对。
#[derive(Clone, Debug)]
pub enum BhpanVersionUploadOutcome {
    Committed { version: BhpanFileVersion },
    OutcomeUnknown { version: Option<BhpanFileVersion> },
}
