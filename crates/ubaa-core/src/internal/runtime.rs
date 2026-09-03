//! 门面工作流共享的私有运行时状态。

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::connection::to_webvpn_url;
use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::internal::route_state::RouteFeatureState;
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::session::{CookieJar, SessionMutation, SessionSnapshot, SessionStore, VersionedSession};

pub(crate) struct ClientRuntime {
    mode: ConnectionMode,
    transport: Arc<dyn HttpTransport>,
    store: Arc<dyn SessionStore>,
    jar: CookieJar,
    authenticated_at: Option<i64>,
    last_activity: Option<i64>,
    account_name: Option<String>,
    session_revision: u64,
    feature_state: Arc<RouteFeatureState>,
}

impl ClientRuntime {
    pub(crate) fn new<T, S>(mode: ConnectionMode, transport: T, store: S) -> Result<Self>
    where
        T: HttpTransport + 'static,
        S: SessionStore + 'static,
    {
        let transport: Arc<dyn HttpTransport> = Arc::new(transport);
        let store: Arc<dyn SessionStore> = Arc::new(store);
        let persisted = store.load_versioned()?;
        Self::from_versioned(mode, transport, store, persisted)
    }

    fn from_versioned(
        mode: ConnectionMode,
        transport: Arc<dyn HttpTransport>,
        store: Arc<dyn SessionStore>,
        persisted: VersionedSession,
    ) -> Result<Self> {
        let mut jar = CookieJar::default();
        let mut authenticated_at = None;
        let mut last_activity = None;
        let mut session_revision = persisted.revision;
        if let Some(snapshot) = persisted.snapshot {
            if snapshot.mode == mode {
                jar.replace(snapshot.cookies);
                authenticated_at = Some(snapshot.authenticated_at);
                last_activity = Some(snapshot.last_activity);
            } else {
                session_revision = match store.compare_exchange(session_revision, None)? {
                    SessionMutation::Applied { revision } => revision,
                    SessionMutation::Conflict => return Err(session_conflict()),
                };
            }
        }
        Ok(Self {
            mode,
            transport,
            store,
            jar,
            authenticated_at,
            last_activity,
            account_name: None,
            session_revision,
            feature_state: Arc::new(RouteFeatureState::default()),
        })
    }

    pub(crate) const fn mode(&self) -> ConnectionMode {
        self.mode
    }

    /// 派生锁定路由的只读运行时，同时丢弃功能范围的服务 Cookie。
    ///
    /// 工作实例共享不可变的传输与存储句柄，但从不持久化认证状态。调用方过滤服务
    /// Cookie，以免并发上游选择状态相互耦合。
    pub(crate) fn fork_for_readonly_with_cookie_filter(
        &self,
        mut retain: impl FnMut(&crate::session::StoredCookie) -> bool,
    ) -> Self {
        let mut jar = CookieJar::default();
        jar.replace(
            self.jar
                .cookies()
                .iter()
                .filter(|cookie| retain(cookie))
                .cloned()
                .collect(),
        );
        Self {
            mode: self.mode,
            transport: Arc::clone(&self.transport),
            store: Arc::clone(&self.store),
            jar,
            authenticated_at: self.authenticated_at,
            last_activity: self.last_activity,
            account_name: self.account_name.clone(),
            session_revision: self.session_revision,
            feature_state: Arc::clone(&self.feature_state),
        }
    }

    pub(crate) fn feature_state(&self) -> Arc<RouteFeatureState> {
        Arc::clone(&self.feature_state)
    }

    pub(crate) fn cookie_value(&mut self, name: &str, request_url: &str) -> Result<Option<String>> {
        self.jar
            .cookie_value_for_url(name, request_url, SystemTime::now())
    }

    pub(crate) fn clear_feature_state(&self) {
        self.feature_state.clear();
    }

    pub(crate) fn has_local_session(&self) -> bool {
        self.authenticated_at.is_some()
    }

    /// 在产生网络副作用前确认本地会话修订仍由当前运行时拥有。
    ///
    /// 只比较单调 CAS 修订，不重新采用外部快照；发现变化后由上层清理内存并拒绝操作。
    pub(crate) fn ensure_session_revision(&self) -> Result<()> {
        if !self.store.is_revision_current(self.session_revision)? {
            return Err(session_conflict());
        }
        Ok(())
    }

    /// 会话为空时同步最新修订，允许随后开始新的登录流程。
    pub(crate) fn sync_empty_session_revision(&mut self) -> Result<()> {
        if !self.has_local_session() {
            self.session_revision = self.store.load_versioned()?.revision;
        }
        Ok(())
    }

    pub(crate) fn account_name(&self) -> Option<&str> {
        self.account_name.as_deref()
    }

    pub(crate) fn remember_account_name(&mut self, account_name: Option<&str>) {
        self.account_name = account_name
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_owned);
    }

    pub(crate) fn url(&self, direct: &str) -> Result<String> {
        match self.mode {
            ConnectionMode::Direct => Ok(direct.into()),
            ConnectionMode::WebVpn => to_webvpn_url(direct),
        }
    }

    pub(crate) async fn request(&mut self, mut request: HttpRequest) -> Result<HttpResponse> {
        let now = SystemTime::now();
        let cookie = self.jar.cookie_header(&request.url, now)?;
        if !cookie.is_empty() {
            request.headers.insert("Cookie".into(), cookie);
        }
        let request_url = request.url.clone();
        let response = self.transport.execute(request).await?;
        self.jar.store_response(&response, &request_url, now)?;
        Ok(response)
    }

    pub(crate) fn refresh_authentication(
        &mut self,
        clear_workflow: &mut (dyn FnMut() + Send),
    ) -> Result<(i64, i64)> {
        let now = now_seconds()?;
        let authenticated_at = self.authenticated_at.unwrap_or(now);
        self.authenticated_at = Some(authenticated_at);
        self.last_activity = Some(now);
        let snapshot = SessionSnapshot {
            mode: self.mode,
            cookies: self.jar.cookies().to_vec(),
            authenticated_at,
            last_activity: now,
        };
        let mutation = match self
            .store
            .compare_exchange(self.session_revision, Some(&snapshot))
        {
            Ok(mutation) => mutation,
            Err(error) => {
                self.clear_memory();
                clear_workflow();
                return Err(error);
            }
        };
        match mutation {
            SessionMutation::Applied { revision } => {
                self.session_revision = revision;
                Ok((authenticated_at, now))
            }
            SessionMutation::Conflict => {
                self.clear_memory();
                clear_workflow();
                Err(session_conflict())
            }
        }
    }

    pub(crate) fn clear_with(&mut self, clear_workflow: impl FnOnce()) -> Result<()> {
        self.clear_memory();
        clear_workflow();
        match self.store.compare_exchange(self.session_revision, None)? {
            SessionMutation::Applied { revision } => {
                self.session_revision = revision;
                Ok(())
            }
            SessionMutation::Conflict => Err(session_conflict()),
        }
    }

    pub(crate) fn clear_memory(&mut self) {
        self.jar = CookieJar::default();
        self.authenticated_at = None;
        self.last_activity = None;
        self.feature_state.clear();
    }

    pub(crate) fn set_session_revision(&mut self, revision: u64) {
        self.session_revision = revision;
    }
}

fn now_seconds() -> Result<i64> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| i64::try_from(duration.as_secs()).unwrap_or(i64::MAX))
        .map_err(|_| {
            UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "system clock is before Unix epoch",
            )
        })
}

fn session_conflict() -> UbaaError {
    UbaaError::new(
        ErrorCode::InternalError,
        ErrorKind::Internal,
        true,
        "local session changed in another process",
    )
}

#[cfg(test)]
mod tests {
    use std::sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    };

    use async_trait::async_trait;

    use super::ClientRuntime;
    use crate::domain::ConnectionMode;
    use crate::error::Result;
    use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
    use crate::session::{FileSessionStore, StoredCookie};

    #[derive(Clone, Default)]
    struct NoopTransport;

    #[async_trait]
    impl HttpTransport for NoopTransport {
        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse> {
            unreachable!("运行时所有权测试不应发出 HTTP 请求")
        }
    }

    #[test]
    fn fork_shares_immutable_handles_and_feature_state_but_isolates_cookies() {
        static NEXT_ID: AtomicU64 = AtomicU64::new(0);
        let root = std::env::temp_dir().join(format!(
            "ubaa-runtime-fork-{}-{}",
            std::process::id(),
            NEXT_ID.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&root);
        let store = FileSessionStore::new(&root).expect("创建运行时测试存储");
        let mut parent =
            ClientRuntime::new(ConnectionMode::WebVpn, NoopTransport, store).expect("创建父运行时");
        parent.jar.replace(vec![
            StoredCookie::fixture("KEEP", "keep-value"),
            StoredCookie::fixture("DROP", "drop-value"),
        ]);
        parent.authenticated_at = Some(101);
        parent.last_activity = Some(202);
        parent.account_name = Some("account-safe".to_owned());
        parent.session_revision = 303;

        let mut child = parent.fork_for_readonly_with_cookie_filter(|cookie| cookie.name == "KEEP");
        assert!(Arc::ptr_eq(&parent.transport, &child.transport));
        assert!(Arc::ptr_eq(&parent.store, &child.store));
        assert!(Arc::ptr_eq(&parent.feature_state, &child.feature_state));
        assert_eq!(child.mode, parent.mode);
        assert_eq!(child.authenticated_at, parent.authenticated_at);
        assert_eq!(child.last_activity, parent.last_activity);
        assert_eq!(child.account_name, parent.account_name);
        assert_eq!(child.session_revision, parent.session_revision);
        assert_eq!(child.jar.cookies().len(), 1);
        assert_eq!(child.jar.cookies()[0].name, "KEEP");

        child
            .jar
            .replace(vec![StoredCookie::fixture("CHILD", "child-value")]);
        assert_eq!(parent.jar.cookies().len(), 2);
        assert_eq!(parent.jar.cookies()[0].name, "KEEP");

        let other_store = FileSessionStore::new(&root).expect("创建独立运行时存储");
        let other = ClientRuntime::new(ConnectionMode::Direct, NoopTransport, other_store)
            .expect("创建独立运行时");
        assert!(!Arc::ptr_eq(&parent.feature_state, &other.feature_state));

        let _ = std::fs::remove_dir_all(root);
    }
}
