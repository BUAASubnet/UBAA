//! In-memory state for one CAS login flow.

use crate::domain::LoginChallenge;

/// Pending login page and challenge scoped to one client instance.
#[derive(Clone, Default)]
pub(crate) struct LoginState {
    page: Option<String>,
    execution: Option<String>,
    challenge: Option<LoginChallenge>,
}

impl std::fmt::Debug for LoginState {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LoginState")
            .field("page", &self.page.as_ref().map(|_| "[REDACTED]"))
            .field("execution", &self.execution.as_ref().map(|_| "[REDACTED]"))
            .field("challenge", &self.challenge.as_ref().map(|_| "[REDACTED]"))
            .finish()
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_formatting_redacts_pending_login_state() {
        let mut state = LoginState::default();
        state.remember(
            "<html>PAGE-SENTINEL</html>".into(),
            "EXECUTION-SENTINEL".into(),
            Some(LoginChallenge {
                id: "CHALLENGE-SENTINEL".into(),
                execution: "EXECUTION-SENTINEL".into(),
                image_data_url: Some("data:image/jpeg;base64,IMAGE-SENTINEL".into()),
            }),
        );

        let formatted = format!("{state:?}");
        for sentinel in [
            "PAGE-SENTINEL",
            "EXECUTION-SENTINEL",
            "CHALLENGE-SENTINEL",
            "IMAGE-SENTINEL",
        ] {
            assert!(
                !formatted.contains(sentinel),
                "leaked {sentinel} in {formatted}"
            );
        }
    }
}
