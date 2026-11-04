use super::{BhpanTransfer, UbaaClient, parse, state::Authority, wire};
use crate::{
    domain::{
        ConnectionMode, SecretValue,
        bhpan::{BhpanPreparedWrite, BhpanTransferPhase, BhpanWriteReceipt},
    },
    error::{Result, UbaaError},
    features::bhpan::{multipart, object, upload::FileSnapshot},
    ports::{HttpMethod, HttpRequest},
};
use serde_json::{Value, json};
use std::path::PathBuf;

pub(super) struct PendingObjectUpload {
    pub(super) source: FileSnapshot,
    parent: Authority,
    name: String,
    base: Option<crate::domain::bhpan::BhpanFileVersion>,
    uploaded: Option<(String, String)>,
    initial_rejection: bool,
    pub(super) transfer: BhpanTransfer,
}
impl Drop for PendingObjectUpload {
    fn drop(&mut self) {
        self.transfer.cancel();
    }
}
impl UbaaClient {
    /// 选择本机文件并准备普通或分片上传，开始写入前仍需消费确认。
    /// # Errors
    /// 文件、目录授权、账号或路线变化时拒绝。
    pub async fn bhpan_prepare_upload(
        &mut self,
        parent: &str,
        path: PathBuf,
        name: &str,
        transfer: BhpanTransfer,
    ) -> Result<BhpanPreparedWrite> {
        transfer.claim()?;
        self.bhpan_scope()?;
        super::write::name(name)?;
        let parent = self.bhpan.item(parent)?;
        parent.folder()?;
        if parent.scope == crate::domain::bhpan::BhpanScope::Recycle {
            return Err(UbaaError::invalid_input("回收站不能上传文件"));
        }
        self.prepare_object_upload(parent, path, name, transfer, None)
            .await
    }
    pub(super) async fn prepare_object_upload(
        &mut self,
        parent: Authority,
        path: PathBuf,
        name: &str,
        transfer: BhpanTransfer,
        base: Option<crate::domain::bhpan::BhpanFileVersion>,
    ) -> Result<BhpanPreparedWrite> {
        let binding = self.bhpan_binding();
        let control = transfer.clone();
        let source = tokio::task::spawn_blocking(move || FileSnapshot::select(path, &control))
            .await
            .map_err(|_| UbaaError::invalid_input("本机文件读取任务未完成"))??;
        self.bhpan_scope()?;
        transfer.ensure_active()?;
        if self.bhpan.binding.as_ref() != Some(&binding) {
            return Err(UbaaError::invalid_input("上传所属账号或路线已变化"));
        }
        transfer.set(BhpanTransferPhase::AwaitingConfirmation, 0, source.length);
        let description = format!("上传 {} 到 {}", name, parent.item.name);
        let upload = PendingObjectUpload {
            source,
            parent,
            name: name.into(),
            transfer,
            base,
            uploaded: None,
            initial_rejection: false,
        };
        let handle = uuid::Uuid::new_v4().to_string();
        self.bhpan.pending.insert(
            handle.clone(),
            super::write::Mutation::object_upload(upload),
        );
        Ok(BhpanPreparedWrite {
            handle,
            description,
            route: ConnectionMode::Direct,
        })
    }
    pub(super) async fn commit_object_upload(
        &mut self,
        upload: Box<PendingObjectUpload>,
    ) -> Result<BhpanWriteReceipt> {
        let (result, _) = self.commit_object_upload_result(upload).await;
        result.map(|()| BhpanWriteReceipt {
            item: None,
            share: None,
        })
    }
    pub(super) async fn commit_object_upload_result(
        &mut self,
        mut upload: Box<PendingObjectUpload>,
    ) -> (Result<()>, Option<crate::domain::bhpan::BhpanFileVersion>) {
        let prepared = (|| {
            upload.source.verify()?;
            upload.transfer.ensure_active()
        })();
        if let Err(error) = prepared {
            return (Err(error), None);
        }
        let token = match &upload.parent.token {
            Some(token) => Ok(token.clone()),
            None => self.bhpan_ready().await,
        };
        let token = match token {
            Ok(token) => token,
            Err(error) => return (Err(error), None),
        };
        self.direct_runtime.begin_non_idempotent_operation();
        let result = self.run_object_upload(&mut upload, &token).await;
        let sent = self.direct_runtime.take_non_idempotent_boundary_crossed();
        let uncertain = sent && !upload.initial_rejection;
        let result = if result.is_err() && uncertain {
            Err(wire::unknown())
        } else {
            result
        };
        let version = upload.uploaded.as_ref().map(|(docid, rev)| {
            let mut authority = upload.parent.clone();
            authority.item.id.clone_from(docid);
            authority.item.kind = crate::domain::bhpan::BhpanItemKind::File;
            authority.item.name.clone_from(&upload.name);
            authority.item.bytes = Some(upload.source.length);
            self.publish_bhpan_version(
                authority,
                rev.clone(),
                upload.source.length,
                upload.name.clone(),
            )
        });
        let phase = if result.is_ok() {
            BhpanTransferPhase::Completed
        } else if uncertain {
            BhpanTransferPhase::OutcomeUnknown
        } else if upload.transfer.progress().phase == BhpanTransferPhase::Cancelled {
            BhpanTransferPhase::Cancelled
        } else {
            BhpanTransferPhase::Failed
        };
        let progress = upload.transfer.progress();
        upload
            .transfer
            .set(phase, progress.bytes, upload.source.length);
        (result, version)
    }
    async fn run_object_upload(
        &mut self,
        upload: &mut PendingObjectUpload,
        token: &SecretValue,
    ) -> Result<()> {
        let length = upload.source.length;
        upload
            .transfer
            .set(BhpanTransferPhase::Submitting, 0, length);
        let mut body = json!({"docid":upload.parent.item.id,"length":length,"name":if upload.base.is_some(){""}else{&upload.name},"ondup":1});
        if let Some(base) = &upload.base {
            body["editedrev"] = json!(base.rev);
        }
        let (docid, rev) = self.upload_objects(upload, token, body).await?;
        upload.source.verify()?;
        upload.transfer.ensure_active()?;
        upload
            .transfer
            .set(BhpanTransferPhase::Finalizing, length, length);
        let mut end = json!({"docid":docid,"rev":rev});
        if let Some(base) = &upload.base {
            end["editedrev"] = json!(base.rev);
        }
        let bytes = self.upload_api("osendupload", end, token, upload).await?;
        let value: Value = parse::json(&bytes)?;
        if !value.is_object() || value.get("error").is_some() {
            return Err(wire::unknown());
        }
        upload.source.verify()?;
        Ok(())
    }
    async fn upload_objects(
        &mut self,
        upload: &mut PendingObjectUpload,
        token: &SecretValue,
        body: Value,
    ) -> Result<(String, String)> {
        let length = upload.source.length;
        let result = if length <= multipart::SMALL_MAX {
            let mut body = body;
            body["client_mtime"] = json!(
                u64::try_from(
                    self.direct_runtime
                        .now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map_err(|_| parse::invalid())?
                        .as_millis()
                )
                .map_err(|_| parse::invalid())?
            );
            let bytes = self
                .upload_api("osbeginupload", body, token, upload)
                .await?;
            let value: Value = parse::json(&bytes)?;
            let docid = parse::field(&bytes, "docid")?;
            let rev = parse::field(&bytes, "rev")?;
            if upload.base.as_ref().is_some_and(|base| base.docid != docid) {
                return Err(parse::invalid());
            }
            upload.uploaded = Some((docid.clone(), rev.clone()));
            let request = object::authorization(
                value.get("authrequest").ok_or_else(parse::invalid)?,
                HttpMethod::Put,
            )?;
            upload
                .transfer
                .set(BhpanTransferPhase::Uploading, 0, length);
            self.upload_range(upload, request, 0, length).await?;
            (docid, rev)
        } else {
            let bytes = self
                .upload_api("osinitmultiupload", body, token, upload)
                .await?;
            let docid = parse::field(&bytes, "docid")?;
            let rev = parse::field(&bytes, "rev")?;
            if upload.base.as_ref().is_some_and(|base| base.docid != docid) {
                return Err(parse::invalid());
            }
            upload.uploaded = Some((docid.clone(), rev.clone()));
            let uploadid = parse::field(&bytes, "uploadid")?;
            let count = length.div_ceil(multipart::PART_SIZE);
            let bytes=self.upload_api("osuploadpart",json!({"docid":docid,"rev":rev,"uploadid":uploadid,"parts":format!("1-{count}")}),token,upload).await?;
            let requests = multipart::parts(&bytes, count)?;
            upload
                .transfer
                .set(BhpanTransferPhase::Uploading, 0, length);
            let mut partinfo = serde_json::Map::new();
            let mut offset = 0u64;
            for (index, request) in requests.into_iter().enumerate() {
                let size = (length - offset).min(multipart::PART_SIZE);
                let response = self.upload_range(upload, request, offset, size).await?;
                let etag = response
                    .header_first("etag")
                    .map(str::trim)
                    .map(|value| value.trim_matches('"'))
                    .filter(|value| !value.is_empty() && !value.contains(['\r', '\n']))
                    .ok_or_else(parse::invalid)?;
                partinfo.insert((index + 1).to_string(), json!([etag, size]));
                offset += size;
            }
            if offset != length {
                return Err(parse::invalid());
            }
            upload
                .transfer
                .set(BhpanTransferPhase::Finalizing, length, length);
            let bytes = self
                .upload_api(
                    "oscompleteupload",
                    json!({"docid":docid,"rev":rev,"uploadid":uploadid,"partinfo":partinfo}),
                    token,
                    upload,
                )
                .await?;
            let (mut request, xml) = object::completion(&bytes)?;
            request.body = xml;
            let original = request.clone();
            let response = self
                .direct_runtime
                .object_upload(request, None, &upload.transfer, || upload.source.verify())
                .await?;
            object::success(&original, &response)?;
            (docid, rev)
        };
        Ok(result)
    }
    async fn upload_api(
        &mut self,
        operation: &str,
        body: Value,
        token: &SecretValue,
        upload: &mut PendingObjectUpload,
    ) -> Result<Vec<u8>> {
        upload.source.verify()?;
        upload.transfer.ensure_active()?;
        let request = wire::request(
            token,
            HttpMethod::Post,
            &format!("{}/file/{operation}", wire::EFAST),
            Some(body),
            None,
        )?;
        let url = request.url.clone();
        let response = tokio::select! {
            biased;
            error=upload.transfer.cancelled()=>return Err(error),
            result=self.direct_runtime.request_bearer_only_checked(request, true, |_| {
                upload.source.verify()?;
                upload.transfer.ensure_active()
            })=>result?,
        };
        if matches!(operation, "osbeginupload" | "osinitmultiupload")
            && response.final_url == url
            && matches!(response.status, 400 | 401 | 403 | 404 | 409)
        {
            upload.initial_rejection = true;
        }
        wire::finish(&url, response, true)
    }

    async fn upload_range(
        &mut self,
        upload: &PendingObjectUpload,
        request: HttpRequest,
        offset: u64,
        length: u64,
    ) -> Result<crate::ports::HttpResponse> {
        if request
            .headers
            .get("content-length")
            .is_some_and(|value| value.parse::<u64>().ok() != Some(length))
        {
            return Err(parse::invalid());
        }
        let body = upload.source.range(offset, length)?;
        let original = request.clone();
        let response = self
            .direct_runtime
            .object_upload(request, Some(body), &upload.transfer, || {
                upload.source.verify()
            })
            .await?;
        object::success(&original, &response)?;
        upload.source.verify()?;
        Ok(response)
    }
}
