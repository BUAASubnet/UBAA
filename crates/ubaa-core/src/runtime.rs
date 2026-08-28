//! 门面工作流共享的私有运行时状态。

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::connection::to_webvpn_url;
use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::features::state::RouteFeatureState;
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::session::{CookieJar, SessionMutation, SessionSnapshot, SessionStore, VersionedSession};

pub(crate) struct ClientRuntime {
    mode: ConnectionMode,
    transport: Arc<dyn HttpTransport>,
    store: Arc<dyn SessionStore>,
    jar: CookieJar,
    authenticated_at: Option<i64>,
    last_activity: Option<i64>,
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
            session_revision: self.session_revision,
            feature_state: Arc::clone(&self.feature_state),
        }
    }

    pub(crate) fn feature_state(&self) -> Arc<RouteFeatureState> {
        Arc::clone(&self.feature_state)
    }

    pub(crate) fn cookie_value(&self, name: &str) -> Option<String> {
        self.jar
            .cookies()
            .iter()
            .find(|cookie| cookie.name == name)
            .map(|cookie| cookie.value.clone())
    }

    pub(crate) fn clear_feature_state(&self) {
        self.feature_state.clear();
    }

    pub(crate) fn has_local_session(&self) -> bool {
        self.authenticated_at.is_some()
    }

    pub(crate) fn url(&self, direct: &str) -> Result<String> {
        match self.mode {
            ConnectionMode::Direct => Ok(direct.into()),
            ConnectionMode::WebVpn => to_webvpn_url(direct),
        }
    }

    /// Cgyy 冻结实现要求始终使用原始直连地址，即使主路线为 `WebVPN`。
    pub(crate) fn direct_url(direct: &str) -> String {
        direct.into()
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
