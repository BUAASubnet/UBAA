//! 宿主在共享读取/独占认证边界内使用的业务读取实例。
use super::UbaaClient;
use crate::auth::AuthWorkflow;
use crate::error::Result;
use std::sync::Arc;

impl UbaaClient {
    /// 派生只读实例；调用方必须保证其请求与主客户端认证及写入互斥。
    ///
    /// 复用连接池并绑定主路线代次，业务状态独立，登录凭据与学校写入被拒绝。
    ///
    /// # Errors
    /// 主客户端会话已失效时拒绝派生。
    pub fn fork_parallel_readonly(&mut self) -> Result<Self> {
        self.direct_runtime.ensure_primary_client()?;
        self.guard_latest_session_ownership()?;
        Ok(Self {
            config_dir: None,
            config: self.config.clone(),
            route_generation: self.route_generation,
            probe: Arc::clone(&self.probe),
            direct_runtime: self.direct_runtime.fork_parallel_readonly(),
            webvpn_runtime: self.webvpn_runtime.fork_parallel_readonly(),
            direct_auth: AuthWorkflow::default(),
            webvpn_auth: AuthWorkflow::default(),
            sessions: self.sessions.clone(),
            interactive: super::interactive_auth::state::InteractiveAuthState::default(),
        })
    }

    /// 在下一批开始前同步主客户端修订；账号、路线或实例变化返回 false。
    ///
    /// # Errors
    /// 外部会话替换或存储故障保持原错误分类。
    pub fn synchronize_parallel_readonly(&mut self, parent: &mut Self) -> Result<bool> {
        parent.guard_latest_session_ownership()?;
        Ok(self.route_generation == parent.route_generation
            && self
                .direct_runtime
                .synchronize_readonly(&parent.direct_runtime)
            && self
                .webvpn_runtime
                .synchronize_readonly(&parent.webvpn_runtime))
    }
}
