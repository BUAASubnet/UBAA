use super::{BhpanTransfer, BhpanUploadSource, UbaaClient, wire};
use crate::domain::bhpan::{BhpanPreparedWrite, BhpanRootKind, BhpanTransferPhase};
use crate::error::{Result, UbaaError};
use crate::features::bhpan::{parse, upload::FileSnapshot};
use crate::ports::HttpMethod;
use serde_json::json;

impl UbaaClient {
    /// 使用有界缓冲计算协议所需摘要，匹配时准备一次秒传确认。
    /// # Errors
    /// 分享目标、文件变化、取消或无法秒传时停止，不自动开始普通上传。
    pub async fn bhpan_prepare_fast_upload(
        &mut self,
        parent: &str,
        source: impl Into<BhpanUploadSource>,
        name: &str,
        transfer: BhpanTransfer,
    ) -> Result<BhpanPreparedWrite> {
        transfer.claim()?;
        let result = self
            .bhpan_prepare_fast_upload_inner(parent, source.into(), name, &transfer)
            .await;
        if let Err(error) = &result {
            let phase = if transfer.progress().phase == BhpanTransferPhase::Cancelled {
                BhpanTransferPhase::Cancelled
            } else if error.code == crate::error::ErrorCode::PermissionDenied {
                BhpanTransferPhase::Blocked
            } else {
                BhpanTransferPhase::Failed
            };
            let p = transfer.progress();
            transfer.set(phase, p.bytes, p.total);
        }
        result
    }
    async fn bhpan_prepare_fast_upload_inner(
        &mut self,
        parent: &str,
        selection: BhpanUploadSource,
        name: &str,
        transfer: &BhpanTransfer,
    ) -> Result<BhpanPreparedWrite> {
        self.bhpan_scope()?;
        let binding = self.bhpan_binding();
        let parent = self.bhpan.item(parent)?;
        parent.personal()?;
        if parent.root_kind == BhpanRootKind::All {
            let token = self.bhpan_ready().await?;
            let personal =
                crate::features::bhpan::read::personal(&mut self.direct_runtime, &token).await?;
            if personal.id != parent.root_id {
                return Err(UbaaError::invalid_input("秒传只支持个人文档库"));
            }
        } else if parent.root_kind != BhpanRootKind::Personal {
            return Err(UbaaError::invalid_input("秒传只支持个人文档库"));
        }
        parent.folder()?;
        super::write::name(name)?;
        transfer.ensure_active()?;
        let control = transfer.clone();
        let source = tokio::task::spawn_blocking(move || FileSnapshot::open(selection, &control))
            .await
            .map_err(|_| UbaaError::invalid_input("本机文件读取任务未完成"))??;
        let token = self.bhpan_ready().await?;
        transfer.ensure_active()?;
        transfer.set(BhpanTransferPhase::Checking, 0, source.length);
        let request = wire::request(
            &token,
            HttpMethod::Post,
            &format!("{}/file/predupload", wire::EFAST),
            Some(json!({"slice_md5":source.slice_md5,"length":source.length})),
            None,
        )?;
        let bytes = tokio::select! {
            biased;
            error=transfer.cancelled()=>return Err(error),
            result=wire::read_checked(&mut self.direct_runtime,request,|_|transfer.ensure_active())=>result?,
        };
        transfer.ensure_active()?;
        let response: serde_json::Value = parse::json(&bytes)?;
        if !response
            .get("match")
            .and_then(serde_json::Value::as_bool)
            .ok_or_else(parse::invalid)?
        {
            return Err(UbaaError::new(
                crate::error::ErrorCode::PermissionDenied,
                crate::error::ErrorKind::Input,
                false,
                "该文件不支持秒传，请改用普通上传",
            ));
        }
        transfer.ensure_active()?;
        let control = transfer.clone();
        let source = tokio::task::spawn_blocking(move || source.full(&control))
            .await
            .map_err(|_| UbaaError::invalid_input("本机文件摘要任务未完成"))??;
        self.bhpan_scope()?;
        if self.bhpan.binding.as_ref() != Some(&binding) {
            return Err(UbaaError::invalid_input("文件任务所属账号或路线已变化"));
        }
        transfer.ensure_active()?;
        let millis = self
            .direct_runtime
            .now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|_| UbaaError::invalid_input("系统时钟无效"))?
            .as_millis();
        let millis = u64::try_from(millis).map_err(|_| UbaaError::invalid_input("系统时钟无效"))?;
        let body = json!({"client_mtime":millis,"crc32":source.crc32,"docid":parent.item.id,"length":source.length,"md5":source.md5,"name":name,"ondup":1});
        let handle = uuid::Uuid::new_v4().to_string();
        let p = BhpanPreparedWrite {
            handle: handle.clone(),
            description: format!(
                "秒传「{name}」到「{}」，{} 字节",
                parent.item.name, source.length
            ),
            route: crate::domain::ConnectionMode::Direct,
        };
        transfer.set(
            BhpanTransferPhase::AwaitingConfirmation,
            source.length,
            source.length,
        );
        self.bhpan.pending.insert(
            handle,
            super::write::Mutation::fast_upload(body, source, transfer.clone()),
        );
        Ok(p)
    }
}
