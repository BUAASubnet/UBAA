//! 版本协议复用云盘认证和流式端口。部署能力保持 Unverified，自动同步须遵守能力状态。
use super::{BhpanTransfer, UbaaClient, parse, state::Authority, wire};
use crate::{
    domain::bhpan::{
        BhpanFileVersion, BhpanItemKind, BhpanPathLookup, BhpanPreparedWrite,
        BhpanVersionDownloadReceipt, BhpanVersionUploadOutcome,
    },
    error::{ErrorCode, Result, UbaaError},
    ports::HttpMethod,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::path::PathBuf;

#[derive(Deserialize)]
struct Metadata {
    docid: String,
    rev: String,
    name: String,
    size: u64,
}

impl UbaaClient {
    /// 从明确个人库逐层定位，未知范围的未找到结果保留 Unknown。
    /// # Errors
    /// 非法名称、歧义、非目录或认证与路线错误时拒绝。
    pub async fn bhpan_lookup_personal_path(
        &mut self,
        components: &[String],
    ) -> Result<BhpanPathLookup> {
        for component in components {
            super::write::name(component)?;
        }
        let mut current = self
            .bhpan_personal_root()
            .await?
            .items
            .into_iter()
            .next()
            .ok_or_else(parse::invalid)?;
        for (index, name) in components.iter().enumerate() {
            let page = self.bhpan_list(&current.handle).await?;
            let mut matched = page.items.into_iter().filter(|item| item.name == *name);
            let next = matched.next();
            if matched.next().is_some() {
                return Err(UbaaError::invalid_input("个人路径存在同名歧义"));
            }
            let Some(next) = next else {
                return Ok(BhpanPathLookup::Unknown {
                    parent: current,
                    remaining: components[index..].to_vec(),
                    range: page.range,
                });
            };
            current = next;
        }
        Ok(BhpanPathLookup::Found(current))
    }
    pub(super) fn publish_bhpan_version(
        &mut self,
        mut authority: Authority,
        rev: String,
        bytes: u64,
        name: String,
    ) -> BhpanFileVersion {
        let handle = self
            .bhpan
            .version_handles
            .entry((authority.item.id.clone(), rev.clone()))
            .or_insert_with(|| uuid::Uuid::new_v4().to_string())
            .clone();
        authority.item.bytes = Some(bytes);
        authority.item.name.clone_from(&name);
        let version = BhpanFileVersion {
            handle: handle.clone(),
            docid: authority.item.id.clone(),
            rev,
            name,
            bytes,
        };
        self.bhpan
            .versions
            .insert(handle, (version.clone(), authority));
        version
    }
    fn version_authority(&mut self, version: &BhpanFileVersion) -> Result<Authority> {
        self.bhpan_scope()?;
        self.bhpan
            .versions
            .get(&version.handle)
            .filter(|(known, _)| known == version)
            .map(|(_, authority)| authority.clone())
            .ok_or_else(|| UbaaError::invalid_input("文件版本快照已失效，请重新读取"))
    }
    /// 读取当前或指定版本元数据，返回绑定当前客户端的非空基版。
    /// # Errors
    /// 缺少或不匹配 docid/rev/name/size、非个人文件或归属失效时拒绝。
    pub async fn bhpan_file_version(
        &mut self,
        item: &str,
        revision: Option<&str>,
    ) -> Result<BhpanFileVersion> {
        self.bhpan_scope()?;
        let authority = self.bhpan.item(item)?;
        authority.personal()?;
        if authority.item.kind != BhpanItemKind::File {
            return Err(UbaaError::invalid_input("版本操作需要个人文件"));
        }
        if revision.is_some_and(str::is_empty) {
            return Err(UbaaError::invalid_input("指定版本不能为空"));
        }
        let token = self.bhpan_ready().await?;
        let mut body = json!({"docid":authority.item.id});
        if let Some(rev) = revision {
            body["rev"] = json!(rev);
        }
        let bytes = wire::api(
            &mut self.direct_runtime,
            &token,
            HttpMethod::Post,
            &format!("{}/file/metadata", wire::EFAST),
            Some(body),
            None,
            false,
        )
        .await?;
        let metadata: Metadata = parse::json(&bytes)?;
        if metadata.docid != authority.item.id
            || metadata.rev.is_empty()
            || metadata.name.is_empty()
            || revision.is_some_and(|rev| rev != metadata.rev)
        {
            return Err(parse::invalid());
        }
        self.guard_latest_session_ownership()?;
        Ok(self.publish_bhpan_version(authority, metadata.rev, metadata.size, metadata.name))
    }
    /// 指定 R 下载并核对响应版本，签名地址继续由同一云盘端口消费。
    /// # Errors
    /// 快照、响应版本/大小/名称、文件交付或取消失败时拒绝。
    pub async fn bhpan_download_file_version(
        &mut self,
        version: &BhpanFileVersion,
        destination: PathBuf,
        overwrite: bool,
        transfer: BhpanTransfer,
    ) -> Result<BhpanVersionDownloadReceipt> {
        transfer.claim()?;
        let result = self
            .download_file_version_inner(version, destination, overwrite, &transfer)
            .await;
        if result.is_err() {
            let p = transfer.progress();
            let phase = if p.phase == crate::domain::bhpan::BhpanTransferPhase::Cancelled {
                p.phase
            } else {
                crate::domain::bhpan::BhpanTransferPhase::Failed
            };
            transfer.set(phase, p.bytes, p.total);
        }
        result
    }
    async fn download_file_version_inner(
        &mut self,
        version: &BhpanFileVersion,
        destination: PathBuf,
        overwrite: bool,
        transfer: &BhpanTransfer,
    ) -> Result<BhpanVersionDownloadReceipt> {
        let authority = self.version_authority(version)?;
        authority.personal()?;
        let token = self.bhpan_ready().await?;
        let url = format!("{}/file/osdownload", wire::EFAST);
        let bytes = tokio::select! {
            biased;
            error=transfer.cancelled()=>return Err(error),
            result=wire::api(
            &mut self.direct_runtime,
            &token,
            HttpMethod::Post,
            &url,
            Some(json!({"docid":version.docid,"rev":version.rev,"authtype":"QUERY_STRING"})),
            None,
            false,
        )=>result?,
        };
        let value: Value = parse::json(&bytes)?;
        if value.get("rev").and_then(Value::as_str) != Some(&version.rev)
            || value.get("size").and_then(Value::as_u64) != Some(version.bytes)
            || value.get("name").and_then(Value::as_str) != Some(&version.name)
            || value
                .get("docid")
                .is_some_and(|docid| docid.as_str() != Some(&version.docid))
        {
            return Err(parse::invalid());
        }
        let request = crate::features::bhpan::object::download(&bytes, false)?;
        self.version_authority(version)?;
        let download = self
            .download_authorized(
                super::download_file::AuthorizedDownload {
                    request,
                    batch: false,
                    expected: Some(version.bytes),
                },
                destination,
                overwrite,
                transfer,
            )
            .await?;
        Ok(BhpanVersionDownloadReceipt {
            version: version.clone(),
            download,
        })
    }
    /// 以已签发基版 R 准备条件更新，开始与最终登记均保留 R。
    /// # Errors
    /// 旧快照、非个人文件或本机文件无效时拒绝。
    pub async fn bhpan_prepare_version_upload(
        &mut self,
        version: &BhpanFileVersion,
        path: PathBuf,
        transfer: BhpanTransfer,
    ) -> Result<BhpanPreparedWrite> {
        transfer.claim()?;
        let authority = self.version_authority(version)?;
        authority.personal()?;
        self.prepare_object_upload(
            authority,
            path.into(),
            &version.name,
            transfer,
            Some(version.clone()),
        )
        .await
    }
    /// 消费同一上传意图，明确交付最终登记结果以及已经取得的新版本 U。
    /// # Errors
    /// 未发送前的输入、认证、归属或确认过期错误保留原错误。
    pub async fn bhpan_commit_upload_version(
        &mut self,
        handle: &str,
    ) -> Result<BhpanVersionUploadOutcome> {
        self.bhpan_scope()?;
        let mutation = self
            .bhpan
            .pending
            .remove(handle)
            .ok_or_else(|| UbaaError::invalid_input("上传确认已消费或失效"))?;
        let (upload, created) = mutation
            .take_object_upload()
            .ok_or_else(|| UbaaError::invalid_input("该确认不是普通或分片上传"))?;
        if created.elapsed() > std::time::Duration::from_mins(5) {
            return Err(UbaaError::invalid_input("上传确认已过期"));
        }
        let (result, version) = self.commit_object_upload_result(upload).await;
        match result {
            Ok(()) => Ok(BhpanVersionUploadOutcome::Committed {
                version: version.ok_or_else(parse::invalid)?,
            }),
            Err(error) if error.code == ErrorCode::OutcomeUnknown => {
                Ok(BhpanVersionUploadOutcome::OutcomeUnknown { version })
            }
            Err(error) => Err(error),
        }
    }
}
