//! 所需路线恢复，不把单路线成功投影为双路线全部就绪。

use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeErrorKind,
    BridgeUserProfile, catch_panic, disposed_error, map_profile,
};
use ubaa_core::facade::{self as core, ReadonlyFeature};

pub mod control;
pub use control::BridgeRequiredRecoveryControl;

impl BridgeClient {
    /// 开始一次首页只读刷新，身份校验仍按各功能实际路线隔离。
    /// # Errors
    /// 已关闭客户端拒绝开始。
    pub async fn begin_read_recovery_batch(&self) -> Result<u32, BridgeError> {
        let mut guard = self.inner.lock().await;
        self.ensure_recovery_allowed().await?;
        Ok(guard
            .as_mut()
            .ok_or_else(disposed_error)?
            .begin_read_recovery_batch())
    }

    /// 结束原刷新批次，旧批次不能清除继任批次。
    /// # Errors
    /// 客户端关闭时返回已关闭错误。
    pub async fn end_read_recovery_batch(&self, batch: u32) -> Result<(), BridgeError> {
        let mut guard = self.inner.lock().await;
        guard
            .as_mut()
            .ok_or_else(disposed_error)?
            .end_read_recovery_batch(batch);
        Ok(())
    }

    /// 显式恢复或认证失败后撤销本轮已校验结果。
    /// # Errors
    /// 客户端关闭时返回已关闭错误。
    pub async fn invalidate_read_recovery_batch(&self) -> Result<(), BridgeError> {
        let mut guard = self.inner.lock().await;
        guard
            .as_mut()
            .ok_or_else(disposed_error)?
            .invalidate_read_recovery_batch();
        Ok(())
    }
}

/// 当前任务需要校验的业务路线；Auto 仍由 Core 功能矩阵决定。
#[derive(Clone, Copy, Debug)]
pub enum BridgeRecoveryFeature {
    Bhpan,
    User,
    Portal,
    Network,
    Finance,
    Ihome,
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
    Connection,
}
impl BridgeRecoveryFeature {
    pub(crate) fn feature(self) -> Option<ReadonlyFeature> {
        Some(match self {
            Self::User | Self::Bhpan | Self::Connection => return None,
            Self::Portal => ReadonlyFeature::Portal,
            Self::Network => ReadonlyFeature::Network,
            Self::Finance => ReadonlyFeature::Finance,
            Self::Ihome => ReadonlyFeature::Ihome,
            BridgeRecoveryFeature::Schedule => ReadonlyFeature::Schedule,
            BridgeRecoveryFeature::Exam => ReadonlyFeature::Exam,
            BridgeRecoveryFeature::Grades => ReadonlyFeature::Grades,
            BridgeRecoveryFeature::Classroom => ReadonlyFeature::Classroom,
            BridgeRecoveryFeature::Spoc => ReadonlyFeature::Spoc,
            BridgeRecoveryFeature::Judge => ReadonlyFeature::Judge,
            BridgeRecoveryFeature::Signin => ReadonlyFeature::Signin,
            BridgeRecoveryFeature::Bykc => ReadonlyFeature::Bykc,
            BridgeRecoveryFeature::LibBook => ReadonlyFeature::LibBook,
            BridgeRecoveryFeature::Cgyy => ReadonlyFeature::Cgyy,
            BridgeRecoveryFeature::Ygdk => ReadonlyFeature::Ygdk,
            BridgeRecoveryFeature::Evaluation => ReadonlyFeature::Evaluation,
        })
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
            let recovered = match feature {
                BridgeRecoveryFeature::Bhpan => client.recover_bhpan_session().await,
                BridgeRecoveryFeature::Connection => client.recover_connection_session().await,
                _ => match feature.feature() {
                    Some(feature) => client.recover_required_session(feature).await,
                    None => client.recover_user_session().await,
                },
            }
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
        self.cancel_bhpan_transfers();
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
    async fn 所需路线恢复通过取票验票返回资料且不访问另一会话() {
        use ubaa_test_support::{
            ExpectedRequest, FileSessionStore, GatewayProbe, HttpMethod, MockTransport,
            RouteConfig, SessionSnapshot, SessionStore,
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
        let url = "https://sso.buaa.edu.cn/serviceValidate?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp&ticket=ST-fixture&format=JSON";
        let target = MockTransport::with_sso_checks([ExpectedRequest::new(
            HttpMethod::Get,
            url,
            ubaa_core::facade::testing::sso_fixture_response(
                200,
                url,
                include_bytes!("../../../../fixtures/auth/userinfo-success.json").to_vec(),
            ),
        )]);
        let sibling = MockTransport::with_sso_checks([]);
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
        assert_eq!(target.requests().unwrap().len(), 2);
        assert_eq!(sibling.requests().unwrap().len(), 0);
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
                resolution: crate::api::write::testing_resolution(BridgeConnectionMode::Direct),
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
