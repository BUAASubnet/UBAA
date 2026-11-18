//! 保存已核验的主会话及处理主会话槽撤销。

use std::sync::Arc;

use crate::error::Result;
use crate::session::business_cache::{Invalidation, revoke_disk};
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
            // 即使无需保存，也必须拒绝外部修订，不能把旧核验结果当作成功。
            if let Err(error) = self.ensure_session_revision() {
                self.clear_memory();
                clear_workflow();
                return Err(error);
            }
            self.revoke_business_after_login(revocation);
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
                self.set_session_revision(revision);
                self.persisted_authentication = Some(Arc::new(snapshot));
                self.revoke_business_after_login(revocation);
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

    fn revoke_business_after_login(&self, event: Option<Invalidation>) {
        let Some(event) = event else { return };
        let result = match (&self.business_sessions, &self.business_session_store) {
            (Some(cache), _) => cache.invalidate(event),
            (None, Some(store)) => revoke_disk(store, event),
            (None, None) => return,
        };
        if result.is_err() {
            tracing::warn!("登录后轮换业务会话缓存撤销令牌失败");
        }
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
