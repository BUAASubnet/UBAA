use serde::Serialize;
use ubaa_core::facade::{
    BhpanDownloadPreparation, BhpanItem, BhpanItemKind, BhpanListRange, BhpanPermission,
    BhpanScope, BhpanShare, BhpanSize,
};
use ubaa_core::facade::{Result, UbaaClient};

/// 可跨进程查询的定位值，不包含 Core 操作句柄。
#[derive(Clone, Debug, Serialize)]
pub struct BhpanEntry {
    pub locator: String,
    pub name: String,
    pub kind: BhpanItemKind,
    pub scope: BhpanScope,
    pub bytes: Option<u64>,
    pub created_at: Option<i64>,
    pub modified_at: Option<i64>,
}
impl BhpanEntry {
    pub(super) fn from_item(client: &mut UbaaClient, item: BhpanItem) -> Result<Self> {
        Ok(Self {
            locator: client.bhpan_item_locator(&item.handle)?,
            name: item.name,
            kind: item.kind,
            scope: item.scope,
            bytes: item.bytes,
            created_at: item.created_at,
            modified_at: item.modified_at,
        })
    }
}
/// 仅在用户显式分享命令中交付链接，密码始终留在 Core。
#[derive(Clone, Debug, Serialize)]
pub struct BhpanShareEntry {
    pub link: String,
    pub title: String,
    pub expires_at: String,
    pub password_required: bool,
    pub limited_times: i64,
    pub permissions: Vec<BhpanPermission>,
    pub can_update: bool,
}
impl BhpanShareEntry {
    pub(super) async fn from_share(client: &mut UbaaClient, share: BhpanShare) -> Result<Self> {
        Ok(Self {
            link: client.bhpan_share_link(&share.handle).await?,
            title: share.title,
            expires_at: share.expires_at,
            password_required: share.password_required,
            limited_times: share.limited_times,
            permissions: share.permissions,
            can_update: share.can_update,
        })
    }
}
#[derive(Clone, Debug, Serialize)]
#[serde(tag = "operation", rename_all = "snake_case")]
pub enum BhpanOutput {
    Login,
    Entries {
        items: Vec<BhpanEntry>,
        range: BhpanListRange,
    },
    Stat {
        item: BhpanEntry,
        size: BhpanSize,
    },
    SuggestedName {
        name: String,
    },
    Shares {
        shares: Vec<BhpanShareEntry>,
    },
    Write {
        item: Option<BhpanEntry>,
        share: Option<BhpanShareEntry>,
    },
    DownloadPreparation {
        preparation: BhpanDownloadPreparation,
    },
}
