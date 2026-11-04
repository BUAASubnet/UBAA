//! 独立北航云盘入口，句柄、授权和单次写入状态由客户端拥有。
mod download;
mod download_file;
mod object_upload;
mod upload;
mod versions;
pub use crate::features::bhpan::transfer::BhpanTransfer;
pub(in crate::facade) mod state;
#[cfg(all(test, feature = "test-contract"))]
mod tests;
#[cfg(all(test, feature = "test-contract"))]
mod transfer_tests;
mod write;
use crate::domain::{
    ConnectionMode, SecretValue,
    bhpan::{
        BhpanCapabilities, BhpanCapability, BhpanListRange, BhpanPage, BhpanRootKind, BhpanScope,
        BhpanShare, BhpanSize,
    },
};
use crate::error::{Result, UbaaError};
use crate::facade::{UbaaClient, types::Operation};
use crate::features::bhpan::{
    auth, parse, read, share,
    wire::{self, EFAST, LINKS},
};
use crate::ports::HttpMethod;
use serde_json::json;
use state::Authority;

impl UbaaClient {
    /// 解析云盘专用能力与实际路线，在任何云盘或恢复业务请求前拒绝未支持路线。
    /// # Errors
    /// 保留实际路线、会话与共享身份错误。
    pub fn resolve_bhpan_route(&mut self) -> super::RoutedResult<()> {
        let resolution = self.resolve_operation(Operation::Bhpan)?;
        Ok(super::Routed {
            data: (),
            resolution,
        })
    }
    /// 校验本机名称，与 GUI 和实际写入共用规则。
    /// # Errors
    /// 名称为空或包含路径分隔符时拒绝。
    pub fn validate_bhpan_name(name: &str) -> Result<()> {
        write::name(name)
    }
    /// 校验分享草稿，不访问账号或网络。
    /// # Errors
    /// 标题、有效期、次数或权限无效时拒绝。
    pub fn validate_bhpan_share_settings(
        settings: &crate::domain::bhpan::BhpanShareSettings,
    ) -> Result<()> {
        write::settings(settings)
    }
    /// 只读定位值来自本客户端本次读取的对象，输入定位值不能签发操作句柄。
    /// # Errors
    /// 句柄已失效时拒绝。
    pub fn bhpan_item_locator(&mut self, handle: &str) -> Result<String> {
        self.bhpan_scope()?;
        Ok(self.bhpan.item(handle)?.item.id)
    }
    /// 返回已实现的能力和仍缺证据的协议边界。
    #[must_use]
    pub fn bhpan_capabilities(&self) -> BhpanCapabilities {
        BhpanCapabilities {
            direct_metadata: BhpanCapability::Available,
            fast_upload: BhpanCapability::Available,
            webvpn: BhpanCapability::Unverified,
            object_transfer: BhpanCapability::Available,
            conditional_replace: BhpanCapability::Unverified,
            limitations: vec![
                "WebVPN 云盘链路尚缺证据".into(),
                "同名条件覆盖尚缺协议证据".into(),
                "列表完整性未知，回收站仅首批 100 项".into(),
                "分享记录缺少目标关联时，需从分享历史管理更新".into(),
            ],
        }
    }
    fn bhpan_scope(&mut self) -> Result<()> {
        self.direct_runtime.ensure_primary_client()?;
        let resolution = self
            .resolve_operation(Operation::Bhpan)
            .map_err(|e| e.error)?;
        if resolution.mode != ConnectionMode::Direct {
            return Err(auth::unavailable());
        }
        let binding = self.bhpan_binding();
        if self.bhpan.binding.as_ref() != Some(&binding) {
            *self.bhpan = state::BhpanState::default();
            self.bhpan.binding = Some(binding);
        }
        Ok(())
    }
    fn bhpan_binding(&self) -> state::Binding {
        state::Binding {
            authentication: self.direct_runtime.authentication_generation(),
            route: self.route_generation,
            lifecycle: self.direct_runtime.feature_state().lifecycle_generation(),
            account: self.direct_runtime.account_name().map(str::to_owned),
        }
    }
    async fn bhpan_ready(&mut self) -> Result<SecretValue> {
        self.bhpan_scope()?;
        if let Some(token) = &self.bhpan.token {
            return Ok(token.clone());
        }
        let token = auth::login(&mut self.direct_runtime).await?;
        self.bhpan.token = Some(token.clone());
        Ok(token)
    }
    fn bhpan_page(
        &mut self,
        items: Vec<parse::Item>,
        scope: BhpanScope,
        token: Option<&SecretValue>,
        context: &str,
    ) -> Result<BhpanPage> {
        self.guard_latest_session_ownership()?;
        let fetched_at = self
            .direct_runtime
            .now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_err(|_| UbaaError::upstream_changed("系统时钟无效"))?
            .as_secs();
        let fetched_at =
            i64::try_from(fetched_at).map_err(|_| UbaaError::upstream_changed("系统时钟无效"))?;
        Ok(BhpanPage {
            items: items
                .into_iter()
                .map(|item| {
                    self.bhpan.publish(Authority {
                        item,
                        scope,
                        token: token.cloned(),
                        context: context.to_owned(),
                    })
                })
                .collect(),
            range: if scope == BhpanScope::Recycle {
                BhpanListRange::FirstHundred
            } else {
                BhpanListRange::Unknown
            },
            route: ConnectionMode::Direct,
            fetched_at,
        })
    }
    /// 复用学校 SSO 激活云盘，不接收另一份凭据。
    /// # Errors
    /// 会话、路线或回调无效时返回安全错误。
    pub async fn bhpan_login(&mut self) -> Result<()> {
        *self.bhpan = state::BhpanState::default();
        self.bhpan_ready().await.map(|_| ())
    }
    /// 浏览个人、共享、部门或群组文档库。
    /// # Errors
    /// 认证、网络或必需字段无效时失败。
    pub async fn bhpan_roots(&mut self, kind: BhpanRootKind) -> Result<BhpanPage> {
        let token = self.bhpan_ready().await?;
        let items = read::roots(&mut self.direct_runtime, &token, kind).await?;
        self.bhpan_page(items, BhpanScope::Personal, None, "")
    }
    /// 读取唯一的个人文档库。
    /// # Errors
    /// 返回数量不为一或认证失效时失败。
    pub async fn bhpan_personal_root(&mut self) -> Result<BhpanPage> {
        let token = self.bhpan_ready().await?;
        let root = read::personal(&mut self.direct_runtime, &token).await?;
        self.bhpan_page(vec![root], BhpanScope::Personal, None, "")
    }
    /// 浏览已签发目录，接收分享继续使用同一分享授权。
    /// # Errors
    /// 句柄、对象类型或授权无效时失败。
    pub async fn bhpan_list(&mut self, parent: &str) -> Result<BhpanPage> {
        self.bhpan_scope()?;
        let a = self.bhpan.item(parent)?;
        a.folder()?;
        if a.scope == BhpanScope::Recycle {
            return Err(UbaaError::invalid_input("回收站条目不能作为普通目录打开"));
        }
        let token = match &a.token {
            Some(token) => token.clone(),
            None => self.bhpan_ready().await?,
        };
        let items = read::list(&mut self.direct_runtime, &token, &a.item.id, false).await?;
        self.bhpan_page(items, a.scope, a.token.as_ref(), &a.context)
    }
    /// 读取目标的文件数、目录数与总字节数。
    /// # Errors
    /// 目标无效、负计数或缺字段时失败。
    pub async fn bhpan_size(&mut self, item: &str) -> Result<BhpanSize> {
        self.bhpan_scope()?;
        let a = self.bhpan.item(item)?;
        if a.scope == BhpanScope::Recycle {
            return Err(UbaaError::invalid_input(
                "回收站条目不能作为普通目标读取属性",
            ));
        }
        let token = match &a.token {
            Some(token) => token.clone(),
            None => self.bhpan_ready().await?,
        };
        let result = wire::api(
            &mut self.direct_runtime,
            &token,
            HttpMethod::Post,
            &format!("{EFAST}/dir/size"),
            Some(json!({"docid":a.item.id,"onlyrecycle":false})),
            None,
            false,
        )
        .await?;
        self.guard_latest_session_ownership()?;
        parse::size(&result)
    }
    /// 获取父目录的一次名称建议，不锁定名称。
    /// # Errors
    /// 分享/回收站目标或返回名称无效时失败。
    pub async fn bhpan_suggest_name(&mut self, parent: &str, name: &str) -> Result<String> {
        let token = self.bhpan_ready().await?;
        let a = self.bhpan.item(parent)?;
        a.personal()?;
        a.folder()?;
        write::name(name)?;
        let bytes = wire::api(
            &mut self.direct_runtime,
            &token,
            HttpMethod::Post,
            &format!("{EFAST}/file/getsuggestname"),
            Some(json!({"docid":a.item.id,"name":name})),
            None,
            false,
        )
        .await?;
        self.guard_latest_session_ownership()?;
        parse::field(&bytes, "name")
    }
    /// 读取回收站首批一百项，不推断完整范围。
    /// # Errors
    /// 个人文档库或回收站响应无效时失败。
    pub async fn bhpan_recycle(&mut self) -> Result<BhpanPage> {
        let token = self.bhpan_ready().await?;
        let root = read::personal(&mut self.direct_runtime, &token).await?;
        let items = read::list(&mut self.direct_runtime, &token, &root.id, true).await?;
        self.bhpan_page(items, BhpanScope::Recycle, None, "")
    }
    /// 查看当前账号的分享历史，密码不进入公开模型。
    /// # Errors
    /// 认证或必需字段无效时失败。
    pub async fn bhpan_share_history(&mut self) -> Result<Vec<BhpanShare>> {
        let token = self.bhpan_ready().await?;
        let bytes = wire::api(
            &mut self.direct_runtime,
            &token,
            HttpMethod::Get,
            "/api/doc-share/v1/docs-shared-with-anyone",
            None,
            None,
            false,
        )
        .await?;
        let records = parse::share_history(&bytes)?;
        self.guard_latest_session_ownership()?;
        Ok(records
            .into_iter()
            .map(|s| self.bhpan.publish_share(s, true))
            .collect())
    }
    /// 查看目标的分享记录，沿用来源固定 folder 路径。
    /// # Errors
    /// 目标或分享字段无效时失败。
    pub async fn bhpan_share_records(&mut self, item: &str) -> Result<Vec<BhpanShare>> {
        let token = self.bhpan_ready().await?;
        let a = self.bhpan.item(item)?;
        a.personal()?;
        let path = format!(
            "{LINKS}/document/folder/{}?type=anonymous",
            wire::segment(&a.item.id)
        );
        let bytes = wire::api(
            &mut self.direct_runtime,
            &token,
            HttpMethod::Get,
            &path,
            None,
            None,
            false,
        )
        .await?;
        let records = parse::share_records(&bytes)?;
        self.guard_latest_session_ownership()?;
        Ok(records
            .into_iter()
            .map(|s| self.bhpan.publish_share(s, false))
            .collect())
    }
    /// 在显式分享交互中交付链接，不用于自动诊断。
    /// # Errors
    /// 当前会话或分享句柄失效时失败。
    pub async fn bhpan_share_link(&mut self, handle: &str) -> Result<String> {
        self.bhpan_ready().await?;
        let (s, _) = self.bhpan.share(handle)?;
        Ok(format!("{}/link/{}", wire::ORIGIN, share::id(&s.id)?))
    }
    /// 打开接收分享，临时 Token 仅在 Core 内保存。
    /// # Errors
    /// 链接、密码、授权或单根目标格式无效时失败。
    pub async fn bhpan_open_share(
        &mut self,
        link: &str,
        password: Option<SecretValue>,
    ) -> Result<BhpanPage> {
        self.bhpan_scope()?;
        let (item, token) = share::open(&mut self.direct_runtime, link, password.as_ref()).await?;
        self.bhpan_page(
            vec![item],
            BhpanScope::ReceivedShare,
            Some(&token),
            &uuid::Uuid::new_v4().to_string(),
        )
    }
}
