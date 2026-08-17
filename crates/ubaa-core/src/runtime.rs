//! Private runtime state shared by facade workflows.

use std::time::{SystemTime, UNIX_EPOCH};

use crate::connection::to_webvpn_url;
use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::session::{CookieJar, SessionMutation, SessionSnapshot, SessionStore, VersionedSession};

pub(crate) struct ClientRuntime {
    mode: ConnectionMode,
    transport: Box<dyn HttpTransport>,
    store: Box<dyn SessionStore>,
    jar: CookieJar,
    authenticated_at: Option<i64>,
    last_activity: Option<i64>,
    session_revision: u64,
}

impl ClientRuntime {
    pub(crate) fn new<T, S>(mode: ConnectionMode, transport: T, store: S) -> Result<Self>
    where
        T: HttpTransport + 'static,
        S: SessionStore + 'static,
    {
        let persisted = store.load_versioned()?;
        Self::from_versioned(mode, transport, store, persisted)
    }

    pub(crate) fn from_versioned<T, S>(
        mode: ConnectionMode,
        transport: T,
        store: S,
        persisted: VersionedSession,
    ) -> Result<Self>
    where
        T: HttpTransport + 'static,
        S: SessionStore + 'static,
    {
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
            transport: Box::new(transport),
            store: Box::new(store),
            jar,
            authenticated_at,
            last_activity,
            session_revision,
        })
    }

    pub(crate) const fn mode(&self) -> ConnectionMode {
        self.mode
    }

    pub(crate) fn authenticated_at(&self) -> Option<i64> {
        self.authenticated_at
    }

    pub(crate) fn has_local_session(&self) -> bool {
        !self.jar.cookies().is_empty() || self.authenticated_at.is_some()
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
        match self
            .store
            .compare_exchange(self.session_revision, Some(&snapshot))?
        {
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

    fn clear_memory(&mut self) {
        self.jar = CookieJar::default();
        self.authenticated_at = None;
        self.last_activity = None;
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
