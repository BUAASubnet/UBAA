use super::{UbaaClient, wire};
use crate::domain::{
    SecretValue,
    bhpan::{BhpanItemKind, BhpanScope},
};
use crate::error::{Result, UbaaError};
use crate::ports::HttpMethod;
use serde_json::json;

impl UbaaClient {
    /// 只向学校请求下载授权，返回方法、主机与头名称，不访问签名目标。
    /// # Errors
    /// 空选择、混合授权、回收站目标或授权结构错误时失败。
    pub(super) async fn bhpan_download_authorization(
        &mut self,
        handles: &[String],
        name: &str,
    ) -> Result<(Vec<u8>, bool, Option<u64>)> {
        self.bhpan_scope()?;
        if handles.is_empty() {
            return Err(UbaaError::invalid_input("请选择下载目标"));
        }
        let items = handles
            .iter()
            .map(|h| self.bhpan.item(h))
            .collect::<Result<Vec<_>>>()?;
        let first = &items[0];
        if items.iter().any(|i| {
            i.scope == BhpanScope::Recycle || i.scope != first.scope || i.context != first.context
        }) {
            return Err(UbaaError::invalid_input(
                "打包下载只能选择同一授权范围的对象",
            ));
        }
        let token: SecretValue = match &first.token {
            Some(t) => t.clone(),
            None => self.bhpan_ready().await?,
        };
        let batch = items.len() > 1 || first.item.kind == BhpanItemKind::Folder;
        let (path, body) = if batch {
            super::write::name(name)?;
            let dirs: Vec<_> = items
                .iter()
                .filter(|i| i.item.kind == BhpanItemKind::Folder)
                .map(|i| &i.item.id)
                .collect();
            let files: Vec<_> = items
                .iter()
                .filter(|i| i.item.kind == BhpanItemKind::File)
                .map(|i| &i.item.id)
                .collect();
            (
                "batchdownload",
                json!({"name":format!("{name}.zip"),"reqhost":"bhpan.buaa.edu.cn","dirs":dirs,"files":files}),
            )
        } else {
            (
                "osdownload",
                json!({"docid":first.item.id,"authtype":"QUERY_STRING"}),
            )
        };
        let bytes = wire::api(
            &mut self.direct_runtime,
            &token,
            HttpMethod::Post,
            &format!("{}/file/{path}", wire::EFAST),
            Some(body),
            None,
            false,
        )
        .await?;
        self.guard_latest_session_ownership()?;
        let expected = (!batch).then_some(first.item.bytes).flatten();
        Ok((bytes, batch, expected))
    }
}

impl UbaaClient {
    /// 读取下载授权的安全摘要，不交付签名地址或头值。
    /// # Errors
    /// 目标、授权或结构不支持时返回稳定错误。
    pub async fn bhpan_download_preparation(
        &mut self,
        handles: &[String],
        name: &str,
    ) -> Result<crate::domain::bhpan::BhpanDownloadPreparation> {
        let (bytes, batch, _) = self.bhpan_download_authorization(handles, name).await?;
        crate::features::bhpan::download::inspect(&bytes, batch)
    }
}
