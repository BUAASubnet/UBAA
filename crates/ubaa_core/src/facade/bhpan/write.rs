use super::{Authority, UbaaClient, parse, share, wire};
use crate::domain::{
    ConnectionMode, SecretValue,
    bhpan::{
        BhpanItemKind, BhpanPreparedWrite, BhpanScope, BhpanShareSettings, BhpanTransferPhase,
        BhpanWriteIntent, BhpanWriteReceipt,
    },
};
use crate::error::{Result, UbaaError};
use crate::ports::HttpMethod;
use serde_json::{Value, json};

pub(super) struct Mutation {
    method: HttpMethod,
    path: String,
    body: Option<Value>,
    secondary: Option<SecretValue>,
    receipt: Receipt,
    created_at: std::time::Instant,
    upload: Option<PendingUpload>,
}
enum Receipt {
    Empty,
    Item(Authority),
    Share(parse::Share),
    UpdateShare(parse::Share),
    FastUpload,
}
struct PendingUpload {
    source: crate::features::bhpan::upload::FileSnapshot,
    transfer: super::BhpanTransfer,
}
impl Drop for PendingUpload {
    fn drop(&mut self) {
        self.transfer.cancel();
    }
}
impl Mutation {
    pub(super) fn fast_upload(
        body: Value,
        source: crate::features::bhpan::upload::FileSnapshot,
        transfer: super::BhpanTransfer,
    ) -> Self {
        Self {
            method: HttpMethod::Post,
            path: format!("{}/file/dupload", wire::EFAST),
            body: Some(body),
            secondary: None,
            receipt: Receipt::FastUpload,
            created_at: std::time::Instant::now(),
            upload: Some(PendingUpload { source, transfer }),
        }
    }
}

pub(super) fn name(name: &str) -> Result<()> {
    if name.trim().is_empty()
        || name.contains(['/', '\\', '\0', '\r', '\n'])
        || matches!(name, "." | "..")
    {
        Err(UbaaError::invalid_input("名称不能为空，也不能含路径分隔符"))
    } else {
        Ok(())
    }
}
pub(super) fn settings(s: &BhpanShareSettings) -> Result<()> {
    if s.title.trim().is_empty()
        || s.limited_times < -1
        || s.limited_times == 0
        || s.permissions.is_empty()
    {
        return Err(UbaaError::invalid_input("分享标题、访问次数或权限无效"));
    }
    chrono::DateTime::parse_from_rfc3339(&s.expires_at)
        .map_err(|_| UbaaError::invalid_input("分享有效期格式无效"))?;
    Ok(())
}
fn share_body(item: &parse::ShareItem, settings: &BhpanShareSettings) -> Value {
    json!({"item":{"id":item.id,"type":item.kind,"allow":settings.permissions},"title":settings.title,
        "expires_at":settings.expires_at,"password":settings.password.expose_secret(),"limited_times":settings.limited_times})
}
fn share_from(item: parse::ShareItem, s: BhpanShareSettings) -> parse::Share {
    parse::Share {
        id: String::new(),
        title: s.title,
        expires_at: s.expires_at,
        password: s.password.expose_secret().to_owned(),
        limited_times: s.limited_times,
        item: parse::ShareItem {
            allow: s.permissions,
            ..item
        },
    }
}

fn summary(state: &super::state::BhpanState, intent: &BhpanWriteIntent) -> Result<String> {
    let result = match &intent {
        BhpanWriteIntent::CreateFolder { parent, name } => {
            format!("在「{}」中新建「{name}」", state.item(parent)?.item.name)
        }
        BhpanWriteIntent::Rename { item, name } => {
            format!("将「{}」重命名为「{name}」", state.item(item)?.item.name)
        }
        BhpanWriteIntent::Move { item, destination }
        | BhpanWriteIntent::Copy { item, destination } => format!(
            "「{}」→「{}」",
            state.item(item)?.item.name,
            state.item(destination)?.item.name
        ),
        BhpanWriteIntent::Recycle { item }
        | BhpanWriteIntent::Restore { item }
        | BhpanWriteIntent::DeleteForever { item }
        | BhpanWriteIntent::CreateShare { item, .. } => state.item(item)?.item.name,
        BhpanWriteIntent::UpdateShare { share, .. } | BhpanWriteIntent::CancelShare { share } => {
            state.share(share)?.0.title
        }
    };
    Ok(result)
}
fn files(
    state: &super::state::BhpanState,
    intent: BhpanWriteIntent,
) -> Result<(Mutation, &'static str)> {
    let copy = matches!(&intent, BhpanWriteIntent::Copy { .. });
    let restore = matches!(&intent, BhpanWriteIntent::Restore { .. });
    let (path, body, receipt, description) = match intent {
        BhpanWriteIntent::CreateFolder { parent, name: n } => {
            name(&n)?;
            let mut a = state.item(&parent)?;
            a.personal()?;
            a.folder()?;
            let body = json!({"docid":a.item.id,"name":n,"ondup":1});
            a.item.name = n;
            a.item.created = None;
            a.item.modified = None;
            (
                format!("{}/dir/create", wire::EFAST),
                Some(body),
                Receipt::Item(a),
                "新建文件夹",
            )
        }
        BhpanWriteIntent::Rename { item, name: n } => {
            name(&n)?;
            let a = state.item(&item)?;
            a.personal()?;
            (
                format!("{}/dir/rename", wire::EFAST),
                Some(json!({"docid":a.item.id,"name":n,"ondup":1})),
                Receipt::Empty,
                "重命名",
            )
        }
        BhpanWriteIntent::Move { item, destination }
        | BhpanWriteIntent::Copy { item, destination } => {
            return relocate(state, &item, &destination, copy);
        }
        BhpanWriteIntent::Recycle { item } => {
            let a = state.item(&item)?;
            a.personal()?;
            (
                format!("{}/file/delete", wire::EFAST),
                Some(json!({"docid":a.item.id})),
                Receipt::Empty,
                "移入回收站",
            )
        }
        BhpanWriteIntent::Restore { item } | BhpanWriteIntent::DeleteForever { item } => {
            let mut a = state.item(&item)?;
            if a.scope != BhpanScope::Recycle {
                return Err(UbaaError::invalid_input("请选择回收站条目"));
            }
            let body = if restore {
                json!({"docid":a.item.id,"ondup":1})
            } else {
                json!({"docid":a.item.id})
            };
            a.scope = BhpanScope::Personal;
            (
                format!(
                    "{}/recycle/{}",
                    wire::EFAST,
                    if restore { "restore" } else { "delete" }
                ),
                Some(body),
                if restore {
                    Receipt::Item(a)
                } else {
                    Receipt::Empty
                },
                if restore {
                    "恢复回收站条目"
                } else {
                    "永久删除，无法恢复"
                },
            )
        }
        _ => return Err(UbaaError::invalid_input("请选择文件管理操作")),
    };
    Ok((
        Mutation {
            method: HttpMethod::Post,
            path,
            body,
            secondary: None,
            receipt,
            created_at: std::time::Instant::now(),
            upload: None,
        },
        description,
    ))
}
fn relocate(
    state: &super::state::BhpanState,
    item: &str,
    destination: &str,
    copy: bool,
) -> Result<(Mutation, &'static str)> {
    let mut secondary = None;
    let (path, body, receipt, description) = {
        let a = state.item(item)?;
        let dest = state.item(destination)?;
        dest.personal()?;
        dest.folder()?;
        if copy {
            if a.scope == BhpanScope::Recycle {
                return Err(UbaaError::invalid_input("请先恢复回收站条目"));
            }
            secondary.clone_from(&a.token);
        } else {
            a.personal()?;
        }
        let path = if copy { "copy" } else { "move" };
        let body = json!({"docid":a.item.id,"destparent":dest.item.id,"ondup":1});
        let a = Authority {
            token: None,
            scope: BhpanScope::Personal,
            context: String::new(),
            ..a
        };
        (
            format!("{}/dir/{path}", wire::EFAST),
            Some(body),
            Receipt::Item(a),
            if copy {
                "复制或另存到个人网盘"
            } else {
                "移动"
            },
        )
    };
    Ok((
        Mutation {
            method: HttpMethod::Post,
            path,
            body,
            secondary,
            receipt,
            created_at: std::time::Instant::now(),
            upload: None,
        },
        description,
    ))
}
fn shares(
    state: &super::state::BhpanState,
    intent: BhpanWriteIntent,
) -> Result<(Mutation, &'static str)> {
    let mut method = HttpMethod::Post;
    let (path, body, receipt, description) = match intent {
        BhpanWriteIntent::CreateShare { item, settings: s } => {
            settings(&s)?;
            let a = state.item(&item)?;
            a.personal()?;
            let item = parse::ShareItem {
                id: Some(a.item.id),
                kind: Some(
                    if a.item.kind == BhpanItemKind::Folder {
                        "folder"
                    } else {
                        "file"
                    }
                    .into(),
                ),
                allow: s.permissions.clone(),
            };
            (
                format!("{}/document/anonymous", wire::LINKS),
                Some(share_body(&item, &s)),
                Receipt::Share(share_from(item, s)),
                "创建分享",
            )
        }
        BhpanWriteIntent::UpdateShare {
            share: h,
            settings: s,
        } => {
            settings(&s)?;
            let (old, can_update) = state.share(&h)?;
            if !can_update {
                return Err(UbaaError::invalid_input(
                    "该分享记录缺少完整目标关联，请从分享历史管理更新",
                ));
            }
            let body = share_body(&old.item, &s);
            let mut updated = share_from(old.item, s);
            updated.id = old.id;
            method = HttpMethod::Put;
            (
                format!(
                    "{}/document/anonymous/{}",
                    wire::LINKS,
                    share::id(&updated.id)?
                ),
                Some(body),
                Receipt::UpdateShare(updated),
                "更新分享",
            )
        }
        BhpanWriteIntent::CancelShare { share: h } => {
            let (s, _) = state.share(&h)?;
            method = HttpMethod::Delete;
            (
                format!("{}/document/anonymous/{}", wire::LINKS, share::id(&s.id)?),
                None,
                Receipt::Empty,
                "取消分享链接",
            )
        }
        _ => return Err(UbaaError::invalid_input("请选择分享管理操作")),
    };
    Ok((
        Mutation {
            method,
            path,
            body,
            secondary: None,
            receipt,
            created_at: std::time::Instant::now(),
            upload: None,
        },
        description,
    ))
}
impl UbaaClient {
    /// 准备一次文件或分享操作，只返回绑定当前目标的确认句柄。
    /// # Errors
    /// 句柄、对象作用域或协议输入无效时不发出业务写入。
    pub async fn bhpan_prepare_write(
        &mut self,
        intent: BhpanWriteIntent,
    ) -> Result<BhpanPreparedWrite> {
        self.bhpan_ready().await?;
        let target = summary(&self.bhpan, &intent)?;
        let (mutation, description) = if matches!(
            &intent,
            BhpanWriteIntent::CreateShare { .. }
                | BhpanWriteIntent::UpdateShare { .. }
                | BhpanWriteIntent::CancelShare { .. }
        ) {
            shares(&self.bhpan, intent)?
        } else {
            files(&self.bhpan, intent)?
        };
        let handle = uuid::Uuid::new_v4().to_string();
        self.bhpan.pending.insert(handle.clone(), mutation);
        Ok(BhpanPreparedWrite {
            handle,
            description: format!("{description}：{target}"),
            route: ConnectionMode::Direct,
        })
    }
    /// 丢弃尚未发送的确认，无学校请求。
    pub fn bhpan_discard_write(&mut self, handle: &str) {
        self.bhpan.pending.remove(handle);
    }

    /// 消费一次性确认，最终业务请求至多发送一次。
    /// # Errors
    /// 发送前拒绝保持明确失败，发送后的不确定收据返回不可重试的结果未知。
    pub async fn bhpan_commit_write(&mut self, handle: &str) -> Result<BhpanWriteReceipt> {
        self.bhpan_scope()?;
        let m = self
            .bhpan
            .pending
            .remove(handle)
            .ok_or_else(|| UbaaError::invalid_input("云盘确认已消费或失效，请重新选择目标"))?;
        if m.created_at.elapsed() > std::time::Duration::from_mins(5) {
            return Err(UbaaError::invalid_input(
                "云盘确认已过期，请刷新目标后重新确认",
            ));
        }
        let token = self.bhpan_ready().await?;
        let request = wire::request(&token, m.method, &m.path, m.body, m.secondary.as_ref())?;
        self.direct_runtime.begin_non_idempotent_operation();
        let bytes = wire::write_checked(&mut self.direct_runtime, request, |_| {
            if let Some(upload) = &m.upload {
                upload.source.verify()?;
                upload.transfer.ensure_active()?;
                let p = upload.transfer.progress();
                upload
                    .transfer
                    .set(BhpanTransferPhase::Submitting, p.bytes, p.total);
            }
            Ok(())
        })
        .await
        .inspect_err(|error| {
            if let Some(upload) = &m.upload {
                let p = upload.transfer.progress();
                upload.transfer.set(
                    if p.phase == BhpanTransferPhase::Cancelled {
                        BhpanTransferPhase::Cancelled
                    } else if error.code == crate::error::ErrorCode::OutcomeUnknown {
                        BhpanTransferPhase::OutcomeUnknown
                    } else {
                        BhpanTransferPhase::Failed
                    },
                    p.bytes,
                    p.total,
                );
            }
        })?;
        let result = (|| {
            let mut result = BhpanWriteReceipt {
                item: None,
                share: None,
            };
            match m.receipt {
                Receipt::Empty => {}
                Receipt::FastUpload => {
                    let value: Value = parse::json(&bytes).map_err(|_| wire::unknown())?;
                    match value.get("success").and_then(Value::as_bool) {
                        Some(true) => {}
                        Some(false) => {
                            return Err(UbaaError::new(
                                crate::error::ErrorCode::UpstreamUnavailable,
                                crate::error::ErrorKind::Upstream,
                                false,
                                "秒传未成功，请先刷新目标后再决定",
                            ));
                        }
                        None => return Err(wire::unknown()),
                    }
                }
                Receipt::Item(mut a) => {
                    a.item.id = parse::field(&bytes, "docid").map_err(|_| wire::unknown())?;
                    result.item = Some(self.bhpan.publish(a));
                }
                Receipt::Share(mut s) => {
                    s.id = parse::field(&bytes, "id").map_err(|_| wire::unknown())?;
                    share::id(&s.id).map_err(|_| wire::unknown())?;
                    result.share = Some(self.bhpan.publish_share(s, true));
                }
                Receipt::UpdateShare(s) => {
                    result.share = Some(self.bhpan.publish_share(s, true));
                }
            }
            Ok(result)
        })();
        if let Some(upload) = &m.upload {
            let p = upload.transfer.progress();
            upload.transfer.set(
                match &result {
                    Ok(_) => BhpanTransferPhase::Completed,
                    Err(error) if error.code == crate::error::ErrorCode::OutcomeUnknown => {
                        BhpanTransferPhase::OutcomeUnknown
                    }
                    Err(_) => BhpanTransferPhase::Failed,
                },
                p.bytes,
                p.total,
            );
        }
        result
    }
}
