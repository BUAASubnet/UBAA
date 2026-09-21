//! 所需路线恢复，不把单路线成功投影为双路线全部就绪。

use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeErrorKind,
    BridgeUserProfile, catch_panic, disposed_error, map_profile,
};
use ubaa_core::facade::{self as core, ReadonlyFeature};

/// 当前任务需要校验的业务路线；Auto 仍由 Core 功能矩阵决定。
#[derive(Clone, Copy, Debug)]
pub enum BridgeRecoveryFeature {
    Schedule,
    Exam,
    Grades,
    Classroom,
    Spoc,
    Judge,
    Signin,
    Bykc,
    LibBook,
    Cgyy,
    Ygdk,
    Evaluation,
}
impl From<BridgeRecoveryFeature> for ReadonlyFeature {
    fn from(value: BridgeRecoveryFeature) -> Self {
        match value {
            BridgeRecoveryFeature::Schedule => Self::Schedule,
            BridgeRecoveryFeature::Exam => Self::Exam,
            BridgeRecoveryFeature::Grades => Self::Grades,
            BridgeRecoveryFeature::Classroom => Self::Classroom,
            BridgeRecoveryFeature::Spoc => Self::Spoc,
            BridgeRecoveryFeature::Judge => Self::Judge,
            BridgeRecoveryFeature::Signin => Self::Signin,
            BridgeRecoveryFeature::Bykc => Self::Bykc,
            BridgeRecoveryFeature::LibBook => Self::LibBook,
            BridgeRecoveryFeature::Cgyy => Self::Cgyy,
            BridgeRecoveryFeature::Ygdk => Self::Ygdk,
            BridgeRecoveryFeature::Evaluation => Self::Evaluation,
        }
    }
}

/// 仅此路线已完成身份验证，不代表其他路线状态。
#[derive(Clone, Debug)]
pub struct BridgeRequiredSession {
    pub route: BridgeConnectionMode,
    pub profile: BridgeUserProfile,
}

impl BridgeClient {
    /// 校验所需路线并在完成后归还客户端锁。
    ///
    /// # Errors
    /// 原路线校验失败、已有学校写意图或客户端失效时返回稳定错误。
    pub async fn recover_required_session(
        &self,
        feature: BridgeRecoveryFeature,
    ) -> Result<BridgeRequiredSession, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let recovered = client
                .recover_required_session(feature.into())
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeRequiredSession {
                route: recovered.resolution.mode.into(),
                profile: map_profile(recovered.data.user),
            })
        })
        .await
    }

    /// 仅向刚校验为缺少认证的目标路线提交获准材料。
    ///
    /// # Errors
    /// 空输入、学校写意图冲突或原认证流程失败时返回稳定错误。
    pub async fn login_required_route(
        &self,
        route: BridgeConnectionMode,
        username: String,
        password: String,
    ) -> Result<BridgeRequiredSession, BridgeError> {
        if username.trim().is_empty() || password.is_empty() {
            return Err(BridgeError::local(
                BridgeErrorCode::InvalidInput,
                BridgeErrorKind::Input,
                false,
                "用户名和密码不能为空",
            ));
        }
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            let recovered = client
                .login_required_route(
                    route.into(),
                    core::LoginInput {
                        username: username.trim().into(),
                        password: core::SecretValue::new(password),
                    },
                )
                .await
                .map_err(|error| BridgeError::from_core(error, Some(route)))?;
            Ok(BridgeRequiredSession {
                route: recovered.pinned_route.into(),
                profile: map_profile(recovered.data),
            })
        })
        .await
    }

    pub(super) async fn ensure_recovery_allowed(&self) -> Result<(), BridgeError> {
        if self.write_intents.lock().await.is_empty() {
            Ok(())
        } else {
            Err(BridgeError::local(
                BridgeErrorCode::OperationConflict,
                BridgeErrorKind::Input,
                true,
                "请先完成当前操作",
            ))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::client::BridgeRoutePolicy;
    use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};

    #[tokio::test]
    async fn required_recovery_returns_profile_after_one_target_status_request() {
        use ubaa_test_support::{
            ExpectedRequest, FileSessionStore, GatewayProbe, HttpMethod, HttpResponse,
            MockTransport, RouteConfig, SessionSnapshot, SessionStore,
        };
        struct NoProbe;
        impl GatewayProbe for NoProbe {
            fn probe(&self, _: std::time::Duration) -> core::NetworkState {
                panic!("固定路线不应探测")
            }
        }
        let root =
            std::env::temp_dir().join(format!("ubaa-required-profile-{}", std::process::id()));
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let store = FileSessionStore::new(&root).unwrap();
        store
            .save(&SessionSnapshot {
                mode: core::ConnectionMode::Direct,
                cookies: Vec::new(),
                authenticated_at: 1000,
                last_activity: 1001,
            })
            .unwrap();
        let url = "https://uc.buaa.edu.cn/api/uc/status";
        let target = MockTransport::new([ExpectedRequest::new(
            HttpMethod::Get,
            url,
            HttpResponse::new(
                200,
                url,
                include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec(),
            ),
        )]);
        let sibling = MockTransport::new([]);
        *client.inner.lock().await = Some(
            core::UbaaClient::with_routing(
                target.clone(),
                sibling.clone(),
                store,
                RouteConfig::parse("[route]\ndefault = \"direct\"\n").unwrap(),
                NoProbe,
            )
            .unwrap(),
        );
        let result = client
            .recover_required_session(BridgeRecoveryFeature::Schedule)
            .await
            .unwrap();
        assert_eq!(result.route, BridgeConnectionMode::Direct);
        assert_eq!(result.profile.username.as_deref(), Some("fixture-user"));
        assert_eq!(target.requests().unwrap().len(), 1);
        assert!(sibling.requests().unwrap().is_empty());
        client.dispose().await.unwrap();
        let _ = std::fs::remove_dir_all(root);
    }

    #[tokio::test]
    async fn required_recovery_preserves_pending_writes_and_disposed_errors() {
        let root =
            std::env::temp_dir().join(format!("ubaa-required-recovery-{}", std::process::id()));
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        client
            .set_default_route_policy(BridgeRoutePolicy::Direct)
            .await
            .unwrap();
        let missing = client
            .recover_required_session(BridgeRecoveryFeature::Schedule)
            .await
            .unwrap_err();
        assert_eq!(missing.code, BridgeErrorCode::AuthenticationRequired);
        assert_eq!(missing.resolved_route, Some(BridgeConnectionMode::Direct));
        client.write_intents.lock().await.insert(
            "synthetic".into(),
            PendingEntry {
                request: PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 1 }),
                expires_at: i64::MAX,
                resolved_route: BridgeConnectionMode::Direct,
                conflict_key: "synthetic".into(),
            },
        );
        assert_eq!(
            client
                .recover_required_session(BridgeRecoveryFeature::Signin)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(
            client
                .login_required_route(
                    BridgeConnectionMode::Direct,
                    "synthetic".into(),
                    "synthetic".into()
                )
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(client.write_intents.lock().await.len(), 1);
        client.dispose().await.unwrap();
        assert_eq!(
            client
                .recover_required_session(BridgeRecoveryFeature::Schedule)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::ClientDisposed
        );
        let _ = std::fs::remove_dir_all(root);
    }
}
