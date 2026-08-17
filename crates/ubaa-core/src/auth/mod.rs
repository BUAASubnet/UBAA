//! In-memory state for one CAS login flow.

use crate::domain::LoginChallenge;

/// Pending login page and challenge scoped to one client instance.
#[derive(Clone, Debug, Default)]
pub(crate) struct LoginState {
    page: Option<String>,
    execution: Option<String>,
    challenge: Option<LoginChallenge>,
}

impl LoginState {
    pub(crate) fn remember(
        &mut self,
        page: String,
        execution: String,
        challenge: Option<LoginChallenge>,
    ) {
        self.page = Some(page);
        self.execution = Some(execution);
        self.challenge = challenge;
    }

    pub(crate) fn page(&self) -> Option<&str> {
        self.page.as_deref()
    }

    pub(crate) fn execution(&self) -> Option<&str> {
        self.execution.as_deref()
    }

    pub(crate) fn challenge(&self) -> Option<&LoginChallenge> {
        self.challenge.as_ref()
    }

    pub(crate) fn clear(&mut self) {
        *self = Self::default();
    }
}
