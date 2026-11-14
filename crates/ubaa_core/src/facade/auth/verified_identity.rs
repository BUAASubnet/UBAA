//! 显式聚合登录生成的不可伪造、不可序列化身份能力。
use super::{ErrorCode, ErrorKind, Result, UbaaClient, UbaaError, UserProfile};
use uuid::Uuid;

/// 只能由当前客户端成功的显式聚合登录签发。普通资料与状态查询不能兑换。
///
/// ```compile_fail
/// use ubaa_core::facade::VerifiedLoginIdentity;
/// let identity = VerifiedLoginIdentity { identity: "任意账号".into() };
/// ```
pub struct VerifiedLoginIdentity {
    identity: String,
    nonce: Uuid,
    generations: (Uuid, Uuid),
}
impl std::fmt::Debug for VerifiedLoginIdentity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("VerifiedLoginIdentity([REDACTED])")
    }
}
impl UbaaClient {
    pub(super) fn login_generations(&self) -> (Uuid, Uuid) {
        (
            self.direct_runtime.authentication_generation(),
            self.webvpn_runtime.authentication_generation(),
        )
    }
    fn guard_login_generations(&mut self) {
        if self.direct_runtime.authentication_revoked()
            || self.webvpn_runtime.authentication_revoked()
            || self.verified_login_generations != Some(self.login_generations())
        {
            self.verified_login = None;
        }
    }

    /// 取出最近一次显式聚合登录的身份能力，仅可取一次。
    ///
    /// # Errors
    /// 没有一致身份、已消费、过期或会话所有权冲突时失败。
    pub fn take_verified_login_identity(&mut self) -> Result<VerifiedLoginIdentity> {
        self.guard_latest_session_ownership()?;
        self.guard_login_generations();
        let (identity, nonce, issued, created) =
            self.verified_login.as_mut().ok_or_else(unverified)?;
        if *issued || created.elapsed() > std::time::Duration::from_mins(5) {
            return Err(unverified());
        }
        *issued = true;
        Ok(VerifiedLoginIdentity {
            identity: identity.clone(),
            nonce: *nonce,
            generations: self.login_generations(),
        })
    }
    /// 在登记关键段重新验证能力所属的客户端、登录代次及双槽会话所有权。
    ///
    /// # Errors
    /// 旧能力、其他客户端能力或外部会话变更均失败，不能恢复外部会话。
    pub fn validate_login_identity(&mut self, identity: &VerifiedLoginIdentity) -> Result<&str> {
        self.guard_latest_session_ownership()?;
        self.guard_login_generations();
        match &self.verified_login {
            Some((value, nonce, true, created))
                if created.elapsed() <= std::time::Duration::from_mins(5)
                    && *nonce == identity.nonce
                    && *value == identity.identity
                    && identity.generations == self.login_generations() =>
            {
                Ok(value)
            }
            _ => Err(unverified()),
        }
    }
    /// 登记持久化后消费能力，后续撤销不能复用同一票据。
    ///
    /// # Errors
    /// 能力过期、被消费或会话所有权失效时返回错误。
    pub fn consume_login_identity(&mut self, identity: &VerifiedLoginIdentity) -> Result<()> {
        self.validate_login_identity(identity)?;
        self.verified_login = None;
        Ok(())
    }
}
pub(super) fn login_identity(profile: &UserProfile, requested: &str) -> Option<String> {
    let identity = profile.school_id.as_deref()?.trim();
    if identity.is_empty() || identity.len() > 128 || identity.chars().any(char::is_control) {
        return None;
    }
    if ![Some(identity), profile.username.as_deref().map(str::trim)]
        .into_iter()
        .flatten()
        .any(|value| value.eq_ignore_ascii_case(requested.trim()))
    {
        return None;
    }
    Some(identity.to_owned())
}
fn unverified() -> UbaaError {
    UbaaError::new(
        ErrorCode::PermissionDenied,
        ErrorKind::Authentication,
        false,
        "显式登录未提供一致且有效的本机登记身份",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn 登录身份接受大小写差异但保留学校学号() {
        let profile = UserProfile {
            school_id: Some("SY-FIXTURE-001".into()),
            username: Some("SY-FIXTURE-001".into()),
            ..UserProfile::default()
        };
        assert_eq!(
            login_identity(&profile, "sy-fixture-001").as_deref(),
            Some("SY-FIXTURE-001")
        );
        assert_eq!(login_identity(&profile, "sy-fixture-002"), None);
    }

    #[test]
    fn 过期身份能力拒绝登记() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../.ubaa_local/agenda_cli_a_fix")
            .join(Uuid::new_v4().simple().to_string());
        let mut client = UbaaClient::open(&root).unwrap();
        let nonce = Uuid::new_v4();
        client.verified_login_generations = Some(client.login_generations());
        client.verified_login = Some((
            "fixture-a".into(),
            nonce,
            false,
            std::time::Instant::now()
                .checked_sub(std::time::Duration::from_secs(301))
                .unwrap(),
        ));
        assert!(client.take_verified_login_identity().is_err());
        client.verified_login.as_mut().unwrap().2 = true;
        let token = VerifiedLoginIdentity {
            identity: "fixture-a".into(),
            nonce,
            generations: client.login_generations(),
        };
        assert!(client.validate_login_identity(&token).is_err());
    }
}
