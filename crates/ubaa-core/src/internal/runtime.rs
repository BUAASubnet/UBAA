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
    non_idempotent_boundary_crossed: bool,
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
            non_idempotent_boundary_crossed: false,
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
            non_idempotent_boundary_crossed: false,
        }
    }

    /// 开始一个不可重放的写操作作用域，并清除上一次操作留下的边界状态。
    pub(crate) fn begin_non_idempotent_operation(&mut self) {
        self.non_idempotent_boundary_crossed = false;
    }

    /// 取走本次写操作的发送边界状态，确保后续操作不会读到陈旧标记。
    pub(crate) fn take_non_idempotent_boundary_crossed(&mut self) -> bool {
        std::mem::take(&mut self.non_idempotent_boundary_crossed)
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

    /// 执行不可自动重放的非幂等请求，并明确区分发送边界。
    ///
    /// Cookie 构造与 Session 修订检查发生在传输调用之前，失败时保留原始错误；
    /// 一旦把请求交给 transport，任何传输、响应体或响应 Cookie 处理失败都只能
    /// 归约为结果未知，调用方必须先读取核对，不能自动重试。
    pub(crate) async fn request_non_idempotent(
        &mut self,
        mut request: HttpRequest,
    ) -> Result<HttpResponse> {
        let now = SystemTime::now();
        let cookie = self.jar.cookie_header(&request.url, now)?;
        if !cookie.is_empty() {
            request.headers.insert("Cookie".into(), cookie);
        }
        self.ensure_session_revision()?;
        let request_url = request.url.clone();
        self.non_idempotent_boundary_crossed = true;
        let response = self
            .transport
            .execute(request)
            .await
            .map_err(|_| write_outcome_unknown())?;
        self.jar
            .store_response(&response, &request_url, now)
            .map_err(|_| write_outcome_unknown())?;
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

fn write_outcome_unknown() -> UbaaError {
    UbaaError::new(
        ErrorCode::OutcomeUnknown,
        ErrorKind::Upstream,
        false,
        "写入结果未知，请先刷新状态再决定是否重试",
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
    use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
    use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
    use crate::session::{
        FileSessionStore, SessionMutation, SessionSnapshot, SessionStore, StoredCookie,
    };

    #[derive(Clone, Default)]
    struct NoopTransport;

    #[async_trait]
    impl HttpTransport for NoopTransport {
        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse> {
            unreachable!("运行时所有权测试不应发出 HTTP 请求")
        }
    }

    #[derive(Clone)]
    struct FailingTransport {
        calls: Arc<AtomicU64>,
    }

    #[async_trait]
    impl HttpTransport for FailingTransport {
        async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse> {
            self.calls.fetch_add(1, Ordering::Relaxed);
            Err(UbaaError::new(
                ErrorCode::UpstreamChanged,
                ErrorKind::Upstream,
                false,
                "fixture response collection failed",
            ))
        }
    }

    #[derive(Clone)]
    struct InvalidCookieTransport {
        calls: Arc<AtomicU64>,
    }

    #[async_trait]
    impl HttpTransport for InvalidCookieTransport {
        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
            self.calls.fetch_add(1, Ordering::Relaxed);
            let mut response = HttpResponse::new(200, request.url, b"{}".to_vec());
            response
                .headers
                .insert("Set-Cookie".to_owned(), vec!["invalid-cookie".to_owned()]);
            Ok(response)
        }
    }

    #[test]
    fn 非幂等请求越过传输边界后的任何失败都归为结果未知() {
        let executor = tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .build()
            .expect("创建测试运行时");
        executor.block_on(async {
            static NEXT_ID: AtomicU64 = AtomicU64::new(0);
            let root = std::env::temp_dir().join(format!(
                "ubaa-runtime-write-boundary-{}-{}",
                std::process::id(),
                NEXT_ID.fetch_add(1, Ordering::Relaxed)
            ));
            let _ = std::fs::remove_dir_all(&root);

            let transport_calls = Arc::new(AtomicU64::new(0));
            let store = FileSessionStore::new(root.join("transport")).expect("创建传输测试存储");
            let mut runtime = ClientRuntime::new(
                ConnectionMode::Direct,
                FailingTransport {
                    calls: Arc::clone(&transport_calls),
                },
                store,
            )
            .expect("创建传输失败运行时");
            runtime.begin_non_idempotent_operation();
            let transport_error = runtime
                .request_non_idempotent(HttpRequest::post("https://example.test/write", Vec::new()))
                .await
                .expect_err("进入 transport 后失败必须为结果未知");
            assert_eq!(transport_error.code, ErrorCode::OutcomeUnknown);
            assert_eq!(transport_calls.load(Ordering::Relaxed), 1);
            assert!(runtime.take_non_idempotent_boundary_crossed());
            assert!(!runtime.take_non_idempotent_boundary_crossed());
            runtime.non_idempotent_boundary_crossed = true;
            runtime.begin_non_idempotent_operation();
            assert!(
                !runtime.take_non_idempotent_boundary_crossed(),
                "上一操作的发送标记不得污染下一操作"
            );

            let cookie_calls = Arc::new(AtomicU64::new(0));
            let store = FileSessionStore::new(root.join("cookie")).expect("创建 Cookie 测试存储");
            let mut runtime = ClientRuntime::new(
                ConnectionMode::Direct,
                InvalidCookieTransport {
                    calls: Arc::clone(&cookie_calls),
                },
                store,
            )
            .expect("创建响应 Cookie 失败运行时");
            runtime.begin_non_idempotent_operation();
            let cookie_error = runtime
                .request_non_idempotent(HttpRequest::post("https://example.test/write", Vec::new()))
                .await
                .expect_err("收到响应后的 Cookie 失败必须为结果未知");
            assert_eq!(cookie_error.code, ErrorCode::OutcomeUnknown);
            assert_eq!(cookie_calls.load(Ordering::Relaxed), 1);
            assert!(runtime.take_non_idempotent_boundary_crossed());

            let _ = std::fs::remove_dir_all(root);
        });
    }

    #[test]
    fn 非幂等请求发送前失败保留原错误且不调用传输() {
        let executor = tokio::runtime::Builder::new_current_thread()
            .enable_time()
            .build()
            .expect("创建测试运行时");
        executor.block_on(async {
            static NEXT_ID: AtomicU64 = AtomicU64::new(0);
            let root = std::env::temp_dir().join(format!(
                "ubaa-runtime-write-before-send-{}-{}",
                std::process::id(),
                NEXT_ID.fetch_add(1, Ordering::Relaxed)
            ));
            let _ = std::fs::remove_dir_all(&root);
            let calls = Arc::new(AtomicU64::new(0));
            let store = FileSessionStore::new(&root).expect("创建发送前测试存储");
            let mut runtime = ClientRuntime::new(
                ConnectionMode::Direct,
                FailingTransport {
                    calls: Arc::clone(&calls),
                },
                store,
            )
            .expect("创建发送前失败运行时");

            runtime.begin_non_idempotent_operation();
            let error = runtime
                .request_non_idempotent(HttpRequest::post("not-a-url", Vec::new()))
                .await
                .expect_err("无效 URL 必须在发送前拒绝");

            assert_ne!(error.code, ErrorCode::OutcomeUnknown);
            assert_eq!(calls.load(Ordering::Relaxed), 0);
            assert!(!runtime.take_non_idempotent_boundary_crossed());

            let revision_root = root.join("revision");
            let revision_store =
                FileSessionStore::new(&revision_root).expect("创建修订冲突测试存储");
            let mut revision_runtime = ClientRuntime::new(
                ConnectionMode::Direct,
                FailingTransport {
                    calls: Arc::clone(&calls),
                },
                revision_store.clone(),
            )
            .expect("创建修订冲突运行时");
            let revision = revision_store
                .load_versioned()
                .expect("读取外部更新前修订")
                .revision;
            let mutation = revision_store
                .compare_exchange(
                    revision,
                    Some(&SessionSnapshot {
                        mode: ConnectionMode::Direct,
                        cookies: Vec::new(),
                        authenticated_at: 1_000,
                        last_activity: 1_001,
                    }),
                )
                .expect("外部更新测试会话");
            assert!(matches!(mutation, SessionMutation::Applied { .. }));
            revision_runtime.begin_non_idempotent_operation();

            let revision_error = revision_runtime
                .request_non_idempotent(HttpRequest::post("https://example.test/write", Vec::new()))
                .await
                .expect_err("发送前修订变化必须拒绝写请求");

            assert_eq!(
                (revision_error.code, revision_error.retryable),
                (ErrorCode::InternalError, true)
            );
            assert_eq!(calls.load(Ordering::Relaxed), 0);
            assert!(!revision_runtime.take_non_idempotent_boundary_crossed());
            let _ = std::fs::remove_dir_all(root);
        });
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
        parent.non_idempotent_boundary_crossed = true;

        let mut child = parent.fork_for_readonly_with_cookie_filter(|cookie| cookie.name == "KEEP");
        assert!(Arc::ptr_eq(&parent.transport, &child.transport));
        assert!(Arc::ptr_eq(&parent.store, &child.store));
        assert!(Arc::ptr_eq(&parent.feature_state, &child.feature_state));
        assert_eq!(child.mode, parent.mode);
        assert_eq!(child.authenticated_at, parent.authenticated_at);
        assert_eq!(child.last_activity, parent.last_activity);
        assert_eq!(child.account_name, parent.account_name);
        assert_eq!(child.session_revision, parent.session_revision);
        assert!(!child.take_non_idempotent_boundary_crossed());
        assert!(parent.take_non_idempotent_boundary_crossed());
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
