//! Stable facade consumed by CLI and future bindings.

use std::path::Path;

use crate::auth::AuthWorkflow;
use crate::domain::{AuthStatus, ConnectionMode, LoginChallenge, LoginInput, UserProfile};
use crate::error::Result;
use crate::features::user;
use crate::ports::{HttpTransport, ReqwestTransport};
use crate::runtime::ClientRuntime;
use crate::session::{FileSessionStore, SessionStore};

/// One independent Direct or `WebVPN` session and login state machine.
pub struct UbaaClient {
    runtime: ClientRuntime,
    auth: AuthWorkflow,
}

impl UbaaClient {
    /// Open a production client using an explicit or persisted connection mode.
    ///
    /// Returns `None` when neither a mode nor a persisted session exists, allowing a host to
    /// render command-specific missing-session behavior without inspecting persistence internals.
    ///
    /// # Errors
    ///
    /// Returns a safe transport or persistence error.
    pub fn open(
        mode: Option<ConnectionMode>,
        config_dir: impl AsRef<Path>,
    ) -> Result<Option<Self>> {
        let store = FileSessionStore::new(config_dir)?;
        let persisted = store.load_versioned()?;
        let Some(mode) = mode.or_else(|| persisted.snapshot.as_ref().map(|snapshot| snapshot.mode))
        else {
            return Ok(None);
        };
        Ok(Some(Self {
            runtime: ClientRuntime::from_versioned(
                mode,
                ReqwestTransport::new()?,
                store,
                persisted,
            )?,
            auth: AuthWorkflow::default(),
        }))
    }

    /// Construct a production client rooted at a host-selected configuration directory.
    ///
    /// # Errors
    ///
    /// Returns a safe transport or persistence error.
    pub fn new(mode: ConnectionMode, config_dir: impl AsRef<Path>) -> Result<Self> {
        Self::with_transport(
            mode,
            ReqwestTransport::new()?,
            FileSessionStore::new(config_dir)?,
        )
    }

    /// Construct a client with injected transport and persistence ports.
    ///
    /// # Errors
    ///
    /// Returns a safe persistence error when an existing session cannot be loaded.
    pub fn with_transport<T, S>(mode: ConnectionMode, transport: T, store: S) -> Result<Self>
    where
        T: HttpTransport + 'static,
        S: SessionStore + 'static,
    {
        Ok(Self {
            runtime: ClientRuntime::new(mode, transport, store)?,
            auth: AuthWorkflow::default(),
        })
    }

    /// Return this client's fixed connection mode.
    #[must_use]
    pub const fn mode(&self) -> ConnectionMode {
        self.runtime.mode()
    }

    /// Load the current SSO page and retain its execution/Cookie challenge in this client.
    ///
    /// # Errors
    ///
    /// Returns a safe network, authentication, or upstream protocol error.
    pub async fn prepare_login(&mut self) -> Result<Option<LoginChallenge>> {
        self.auth.prepare_login(&mut self.runtime).await
    }

    /// Submit one credential/captcha form, activate User Center, and return its parsed profile.
    ///
    /// # Errors
    ///
    /// Returns a stable input, captcha, authentication, network, or upstream error.
    pub async fn login(&mut self, input: LoginInput) -> Result<UserProfile> {
        self.auth.login(&mut self.runtime, input).await
    }

    /// Validate the current User Center session and refresh last activity.
    ///
    /// # Errors
    ///
    /// Returns authentication-required for explicit invalidation while preserving state on timeout/5xx.
    pub async fn auth_status(&mut self) -> Result<AuthStatus> {
        let mut clear_workflow = || self.auth.clear();
        user::auth_status(&mut self.runtime, &mut clear_workflow).await
    }

    /// Fetch and parse the latest User Center profile.
    ///
    /// # Errors
    ///
    /// Returns a stable authentication, network, availability, or parsing error.
    pub async fn get_user_info(&mut self) -> Result<UserProfile> {
        let mut clear_workflow = || self.auth.clear();
        user::get_user_info(&mut self.runtime, &mut clear_workflow).await
    }

    /// Best-effort remote logout followed by unconditional cleanup of this client's memory.
    ///
    /// # Errors
    ///
    /// Returns a persistence/revision error; remote logout failures are intentionally ignored.
    pub async fn logout(&mut self) -> Result<()> {
        self.auth.logout(&mut self.runtime).await
    }
}
