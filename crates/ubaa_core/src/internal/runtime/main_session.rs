//! 保存已核验的主会话及处理主会话槽撤销。

use std::sync::Arc;

use crate::error::Result;
use crate::session::business_cache::Invalidation;
use crate::session::{SessionMutation, SessionSnapshot};

use super::{ClientRuntime, now_seconds_at, session_conflict};

const SESSION_ACTIVITY_SAVE_INTERVAL_SECS: i64 = 60;

impl ClientRuntime {
    pub(crate) fn refresh_authentication(
        &mut self,
        clear_workflow: &mut (dyn FnMut() + Send),
    ) -> Result<(i64, i64)> {
        let revocation = self
            .persisted_authentication
            .is_none()
            .then_some(Invalidation::AccountChanged);
        self.refresh_main_session(clear_workflow, revocation)
    }

    pub(crate) fn refresh_authentication_for_login(
        &mut self,
        clear_workflow: &mut (dyn FnMut() + Send),
        verified_account: Option<&str>,
    ) -> Result<(i64, i64)> {
        self.refresh_main_session(
            clear_workflow,
            Some(self.login_revocation(verified_account)),
        )
    }

    fn refresh_main_session(
        &mut self,
        clear_workflow: &mut (dyn FnMut() + Send),
        revocation: Option<Invalidation>,
    ) -> Result<(i64, i64)> {
        self.check_authentication_scope()?;
        let now = now_seconds_at(self.now())?;
        let authenticated_at = self.authenticated_at.unwrap_or(now);
        self.authenticated_at = Some(authenticated_at);
        self.last_activity = Some(now);
        if self.readonly_generation.is_some() {
            self.ensure_session_revision()?;
            return Ok((authenticated_at, now));
        }
        if self.persisted_authentication.as_ref().is_some_and(|saved| {
            authenticated_at == saved.authenticated_at
                && now.saturating_sub(saved.last_activity) < SESSION_ACTIVITY_SAVE_INTERVAL_SECS
                && self.jar.matches_persisted(&saved.cookies)
        }) {
            #[cfg(test)]
            if let Some(before_revocation) = self.before_login_revocation.take() {
                before_revocation();
            }
            if let Err(error) = self.check_revision_without_save(revocation) {
                self.clear_memory();
                clear_workflow();
                return Err(error);
            }
            return Ok((authenticated_at, now));
        }
        let snapshot = SessionSnapshot {
            mode: self.mode,
            cookies: self.jar.cookies().to_vec(),
            authenticated_at,
            last_activity: now,
        };
        let _permit = self
            .shared_account
            .as_ref()
            .map(crate::facade::SharedAccountGuard::acquire)
            .transpose()?;
        let mutation = match &self.coordinated_store {
            Some(store) => store.compare_exchange_with_revocation(
                self.session_revision,
                Some(&snapshot),
                revocation,
            ),
            None => self
                .store
                .compare_exchange(self.session_revision, Some(&snapshot)),
        };
        let mutation = match mutation {
            Ok(mutation) => mutation,
            Err(error) => {
                self.clear_memory();
                clear_workflow();
                return Err(error);
            }
        };
        match mutation {
            SessionMutation::Applied { revision } => {
                self.set_session_revision(revision);
                self.persisted_authentication = Some(Arc::new(snapshot));
                Ok((authenticated_at, now))
            }
            SessionMutation::Conflict => {
                self.clear_memory();
                clear_workflow();
                Err(session_conflict())
            }
        }
    }

    fn login_revocation(&self, verified_account: Option<&str>) -> Invalidation {
        if self.account_name().is_some() && self.account_name() == verified_account {
            Invalidation::SameAccountLogin(self.mode)
        } else {
            Invalidation::AccountChanged
        }
    }

    fn check_revision_without_save(&self, event: Option<Invalidation>) -> Result<()> {
        let (Some(event), Some(store)) = (event, &self.coordinated_store) else {
            return self.ensure_session_revision();
        };
        let _permit = self
            .shared_account
            .as_ref()
            .map(crate::facade::SharedAccountGuard::acquire)
            .transpose()?;
        if store
            .revoke_business_for_login(self.session_revision, event)?
            .is_err()
        {
            tracing::warn!("登录准备轮换业务会话缓存撤销令牌失败");
        }
        Ok(())
    }

    pub(crate) fn clear_with(&mut self, clear_workflow: impl FnOnce()) -> Result<()> {
        self.clear_memory();
        clear_workflow();
        if self.readonly_generation.is_some() {
            return Ok(());
        }
        let _permit = self
            .shared_account
            .as_ref()
            .map(crate::facade::SharedAccountGuard::acquire)
            .transpose()?;
        match self.store.compare_exchange(self.session_revision, None)? {
            SessionMutation::Applied { revision } => {
                self.set_session_revision(revision);
                Ok(())
            }
            SessionMutation::Conflict => Err(session_conflict()),
        }
    }
}
