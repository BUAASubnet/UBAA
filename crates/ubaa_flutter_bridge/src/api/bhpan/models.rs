//! 网盘 typed 投影，不携带业务 Token、签名地址或响应正文。
use crate::api::client::BridgeConnectionMode;

#[derive(Clone, Copy, Debug)]
pub enum BridgeBhpanRootKind {
    All,
    Personal,
    Shared,
    Department,
    Group,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeBhpanItemKind {
    File,
    Folder,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeBhpanScope {
    Personal,
    ReceivedShare,
    Recycle,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeBhpanListRange {
    Unknown,
    FirstHundred,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeBhpanPermission {
    Create,
    Modify,
    Download,
    Preview,
    Display,
}

#[derive(Clone, Debug)]
pub struct BridgeBhpanItem {
    pub handle: String,
    pub name: String,
    pub kind: BridgeBhpanItemKind,
    pub scope: BridgeBhpanScope,
    pub bytes: Option<u64>,
    pub created_at: Option<i64>,
    pub modified_at: Option<i64>,
}
#[derive(Clone, Debug)]
pub struct BridgeBhpanPage {
    pub items: Vec<BridgeBhpanItem>,
    pub range: BridgeBhpanListRange,
    pub route: BridgeConnectionMode,
    pub fetched_at: i64,
}
#[derive(Clone, Debug)]
pub struct BridgeBhpanSize {
    pub folders: u64,
    pub files: u64,
    pub bytes: u64,
}
#[derive(Clone, Debug)]
pub struct BridgeBhpanShare {
    pub handle: String,
    pub title: String,
    pub expires_at: String,
    pub password_required: bool,
    pub limited_times: i64,
    pub permissions: Vec<BridgeBhpanPermission>,
    pub can_update: bool,
}
pub struct BridgeBhpanShareSettings {
    pub title: String,
    pub expires_at: String,
    pub password: String,
    pub limited_times: i64,
    pub permissions: Vec<BridgeBhpanPermission>,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeBhpanReadView {
    PersonalRoot,
    Roots,
    List,
    Recycle,
    OpenShare,
}
pub struct BridgeBhpanQuery {
    pub view: BridgeBhpanReadView,
    pub root: Option<BridgeBhpanRootKind>,
    pub target: Option<String>,
    pub link: Option<String>,
    pub password: Option<String>,
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeBhpanMutationKind {
    CreateFolder,
    Rename,
    Move,
    Copy,
    Recycle,
    Restore,
    DeleteForever,
    CreateShare,
    UpdateShare,
    CancelShare,
}
pub struct BridgeBhpanWrite {
    pub kind: BridgeBhpanMutationKind,
    pub target: String,
    pub name: Option<String>,
    pub destination: Option<String>,
    pub settings: Option<BridgeBhpanShareSettings>,
}
#[derive(Clone, Debug)]
pub struct BridgeBhpanPrepared {
    pub handle: String,
    pub description: String,
    pub route: BridgeConnectionMode,
}
#[derive(Clone, Debug)]
pub struct BridgeBhpanReceipt {
    pub item: Option<BridgeBhpanItem>,
    pub share: Option<BridgeBhpanShare>,
}
#[derive(Clone, Debug)]
pub struct BridgeBhpanCapabilities {
    pub direct_metadata: BridgeBhpanCapability,
    pub fast_upload: BridgeBhpanCapability,
    pub webvpn: BridgeBhpanCapability,
    pub object_transfer: BridgeBhpanCapability,
    pub conditional_replace: BridgeBhpanCapability,
    pub limitations: Vec<String>,
}

#[derive(Clone, Copy, Debug)]
pub enum BridgeBhpanTransferPhase {
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
}
#[derive(Clone, Debug)]
pub struct BridgeBhpanTransferProgress {
    pub phase: BridgeBhpanTransferPhase,
    pub bytes: u64,
    pub total: u64,
}

#[derive(Clone, Debug)]
pub struct BridgeBhpanDownloadPreparation {
    pub host: String,
    pub port: u16,
    pub method: String,
    pub header_names: Vec<String>,
    pub batch: bool,
    pub destination_verified: bool,
}

#[derive(Clone, Copy, Debug)]
pub enum BridgeBhpanCapability {
    Available,
    Unverified,
    Unavailable,
}
