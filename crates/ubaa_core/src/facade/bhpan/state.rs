use crate::domain::{
    SecretValue,
    bhpan::{BhpanItem, BhpanItemKind, BhpanScope, BhpanShare},
};
use crate::error::{Result, UbaaError};
use crate::features::bhpan::parse;
use std::collections::HashMap;

#[derive(Clone)]
pub(super) struct Authority {
    pub item: parse::Item,
    pub scope: BhpanScope,
    pub token: Option<SecretValue>,
    pub context: String,
}
impl Authority {
    pub(super) fn personal(&self) -> Result<()> {
        if self.scope == BhpanScope::Personal {
            Ok(())
        } else {
            Err(UbaaError::invalid_input("该操作需要个人文档库目标"))
        }
    }
    pub(super) fn folder(&self) -> Result<()> {
        if self.item.kind == BhpanItemKind::Folder {
            Ok(())
        } else {
            Err(UbaaError::invalid_input("请选择文件夹"))
        }
    }
}
#[derive(Default)]
pub(in crate::facade) struct BhpanState {
    pub(super) binding: Option<Binding>,
    pub(super) token: Option<SecretValue>,
    pub(super) items: HashMap<String, Authority>,
    item_handles: HashMap<ItemKey, String>,
    pub(super) shares: HashMap<String, (parse::Share, bool)>,
    share_handles: HashMap<String, String>,
    pub(super) pending: HashMap<String, super::write::Mutation>,
}
#[derive(Hash, Eq, PartialEq)]
struct ItemKey {
    id: String,
    scope: BhpanScope,
    context: String,
}
#[derive(Eq, PartialEq)]
pub(super) struct Binding {
    pub authentication: uuid::Uuid,
    pub route: u64,
    pub lifecycle: u64,
    pub account: Option<String>,
}
impl BhpanState {
    pub(super) fn item(&self, handle: &str) -> Result<Authority> {
        self.items
            .get(handle)
            .cloned()
            .ok_or_else(|| UbaaError::invalid_input("云盘目标已失效，请刷新后重新选择"))
    }
    pub(super) fn share(&self, handle: &str) -> Result<(parse::Share, bool)> {
        self.shares
            .get(handle)
            .cloned()
            .ok_or_else(|| UbaaError::invalid_input("分享记录已失效，请刷新后重新选择"))
    }
    pub(super) fn publish(&mut self, authority: Authority) -> BhpanItem {
        let key = ItemKey {
            id: authority.item.id.clone(),
            scope: authority.scope,
            context: authority.context.clone(),
        };
        let handle = self
            .item_handles
            .entry(key)
            .or_insert_with(|| uuid::Uuid::new_v4().to_string())
            .clone();
        let item = BhpanItem {
            handle: handle.clone(),
            name: authority.item.name.clone(),
            kind: authority.item.kind,
            scope: authority.scope,
            bytes: authority.item.bytes,
            created_at: authority.item.created,
            modified_at: authority.item.modified,
        };
        self.items.insert(handle, authority);
        item
    }
    pub(super) fn publish_share(&mut self, share: parse::Share, can_update: bool) -> BhpanShare {
        let handle = self
            .share_handles
            .entry(share.id.clone())
            .or_insert_with(|| uuid::Uuid::new_v4().to_string())
            .clone();
        let result = BhpanShare {
            handle: handle.clone(),
            title: share.title.clone(),
            expires_at: share.expires_at.clone(),
            password_required: !share.password.is_empty(),
            limited_times: share.limited_times,
            permissions: share.item.allow.clone(),
            can_update,
        };
        self.shares.insert(handle, (share, can_update));
        result
    }
}
