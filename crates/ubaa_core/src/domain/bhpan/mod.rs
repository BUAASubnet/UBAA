//! 北航云盘的安全领域投影。所有句柄只在签发客户端与当前会话内有效。
use super::{ConnectionMode, SecretValue};
use serde::{Deserialize, Serialize};

/// 可浏览的文档库分类。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BhpanRootKind {
    All,
    Personal,
    Shared,
    Department,
    Group,
}

/// 对象类型来自上游 size=-1 约定或文档库类型。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BhpanItemKind {
    File,
    Folder,
}

/// 授权来源，临时授权值不跨出 Core。
#[derive(Clone, Copy, Debug, Deserialize, Eq, Hash, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BhpanScope {
    Personal,
    ReceivedShare,
    Recycle,
}

/// 读取返回的对象，不以裸 docid 作为宿主操作权限。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanItem {
    pub handle: String,
    pub name: String,
    pub kind: BhpanItemKind,
    pub scope: BhpanScope,
    pub bytes: Option<u64>,
    pub created_at: Option<i64>,
    pub modified_at: Option<i64>,
}

/// 来源没有分页结束证明时保留未知范围。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BhpanListRange {
    Unknown,
    FirstHundred,
}

/// 当前请求取得的列表，不持久化临时授权。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanPage {
    pub items: Vec<BhpanItem>,
    pub range: BhpanListRange,
    pub route: ConnectionMode,
    pub fetched_at: i64,
}

/// 目标统计。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanSize {
    pub folders: u64,
    pub files: u64,
    pub bytes: u64,
}

/// 分享允许的五项上游权限。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum BhpanPermission {
    Create,
    Modify,
    Download,
    Preview,
    Display,
}

/// 分享输入，密码在 Debug 和通用序列化中遮盖。
#[derive(Clone, Debug, Serialize)]
pub struct BhpanShareSettings {
    pub title: String,
    pub expires_at: String,
    pub password: SecretValue,
    pub limited_times: i64,
    pub permissions: Vec<BhpanPermission>,
}

/// 分享的安全投影。链接只由显式交付方法取得。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanShare {
    pub handle: String,
    pub title: String,
    pub expires_at: String,
    pub password_required: bool,
    pub limited_times: i64,
    pub permissions: Vec<BhpanPermission>,
    pub can_update: bool,
}

/// 一次性写入意图，输入只引用 Core 签发的对象句柄。
#[derive(Clone, Debug)]
pub enum BhpanWriteIntent {
    CreateFolder {
        parent: String,
        name: String,
    },
    Rename {
        item: String,
        name: String,
    },
    Move {
        item: String,
        destination: String,
    },
    Copy {
        item: String,
        destination: String,
    },
    Recycle {
        item: String,
    },
    Restore {
        item: String,
    },
    DeleteForever {
        item: String,
    },
    CreateShare {
        item: String,
        settings: BhpanShareSettings,
    },
    UpdateShare {
        share: String,
        settings: BhpanShareSettings,
    },
    CancelShare {
        share: String,
    },
}

/// 可以呈现给用户的一次性确认。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanPreparedWrite {
    pub handle: String,
    pub description: String,
    pub route: ConnectionMode,
}

/// 写入安全收据，新的对象身份在 Core 内保存，不公开传输凭据。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanWriteReceipt {
    pub item: Option<BhpanItem>,
    pub share: Option<BhpanShare>,
}

/// 实际实现与协议证据分别表达。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanCapabilities {
    pub direct_metadata: BhpanCapability,
    pub fast_upload: BhpanCapability,
    pub webvpn: BhpanCapability,
    pub object_transfer: BhpanCapability,
    pub conditional_replace: BhpanCapability,
    pub limitations: Vec<String>,
}

/// 下载授权的脱敏准备摘要，仅描述学校返回的目标，不发送对象请求。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanDownloadPreparation {
    pub host: String,
    pub port: u16,
    pub method: String,
    pub header_names: Vec<String>,
    pub batch: bool,
    pub destination_verified: bool,
}

/// 大文件摘要与上传阶段，只包含进度和安全状态。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BhpanTransferPhase {
    Queued,
    HashingMini,
    HashingFull,
    Checking,
    AwaitingConfirmation,
    Submitting,
    Completed,
    Cancelled,
    Failed,
    OutcomeUnknown,
    Blocked,
    Uploading,
    Downloading,
    Finalizing,
}
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanTransferProgress {
    pub phase: BhpanTransferPhase,
    pub bytes: u64,
    pub total: u64,
}

/// 能力的实现与协议证据状态。
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum BhpanCapability {
    Available,
    Unverified,
    Unavailable,
}

/// 文件已完整写入用户选择的位置，不包含下载授权。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct BhpanDownloadReceipt {
    pub bytes: u64,
    pub batch: bool,
}

mod version;
pub use version::*;
