//! 命令使用同一准备意图、一次性消费、发送观察和缓存核对提示。
use super::{
    dispatch::{WriteReceipt, dispatch},
    preparation_error::routed_bridge_error,
};
use crate::api::{
    client::{BridgeClient, disposed_error},
    offline::BridgeOfflineCache,
};
use futures_util::FutureExt;
use ubaa_core::facade as core;

pub(crate) type CommandHint = (core::OfflineCache, String);
pub(crate) struct CommandCommit {
    pub(crate) result: core::RoutedResult<WriteReceipt>,
    pub(crate) hint: Option<CommandHint>,
}
impl BridgeClient {
    pub(crate) async fn commit_command_write(
        &self,
        cache: Option<&BridgeOfflineCache>,
        id: &str,
        command: Option<&crate::api::command::BridgeCommand>,
    ) -> core::Result<CommandCommit> {
        let mut guard = self.inner.lock().await;
        let entry = self
            .take_write_entry(id)
            .await
            .map_err(|e| routed_bridge_error(e).error)?;
        let client = guard
            .as_mut()
            .ok_or_else(|| routed_bridge_error(disposed_error()).error)?;
        let operation = entry.request.operation();
        let impact = entry.request.cache_impact();
        let route = entry.resolved_route;
        let observation = std::sync::Arc::new(client.observe_write_boundary());
        if let Some(command) = command {
            *command.sent.lock().unwrap() = Some((observation.clone(), entry.resolution));
        }
        let mut cleanup = CommandEffects {
            cache: cache.map(|v| v.cache.clone()),
            observation: observation.clone(),
            route: route.into(),
            impact,
            hint: None,
            finished: false,
        };
        let (mut ticket, hint_error) = super::readback::begin_hint(cache, operation, route).await;
        cleanup.hint = ticket.as_ref().map(|v| v.id().to_owned());
        let raw = std::panic::AssertUnwindSafe(dispatch(client, entry.request, route.into()))
            .catch_unwind()
            .await;
        let result = raw.unwrap_or_else(|_| {
            Err(core::RoutedError {
                error: core::UbaaError::new(
                    if observation.may_have_been_sent() {
                        core::ErrorCode::OutcomeUnknown
                    } else {
                        core::ErrorCode::InternalError
                    },
                    core::ErrorKind::Internal,
                    false,
                    "学校写入没有取得可确认的结果，请先只读核对",
                ),
                resolution: None,
            })
        });
        let projected = super::commit::project_dispatch_result(result.clone(), operation, route);
        let sent = observation.may_have_been_sent();
        if !sent {
            let _ = super::readback::finish_hint(cache, ticket.take(), &projected).await;
        }
        let cached =
            super::cache::finish_cached_commit(cache, cleanup.impact.clone(), route, projected)
                .await;
        if hint_error.is_some() || cached.cache_error.is_some() {
            tracing::warn!("学校操作的本地缓存处理未完成");
        }
        let hint = if sent {
            cache
                .zip(ticket)
                .map(|(cache, ticket)| (cache.cache.clone(), ticket.id().to_owned()))
        } else {
            None
        };
        cleanup.finished = true;
        Ok(CommandCommit { result, hint })
    }
}
pub(crate) fn reservation_selection(
    request: &core::CgyyReservationSubmitRequest,
) -> super::BridgeCgyySubmitReservationRequest {
    super::BridgeCgyySubmitReservationRequest {
        venue_site_id: request.venue_site_id,
        reservation_date: request.reservation_date.clone(),
        selections: request
            .selections
            .iter()
            .map(|v| super::BridgeCgyyReservationSelection {
                space_id: v.space_id,
                time_id: v.time_id,
                venue_space_group_id: v.venue_space_group_id,
            })
            .collect(),
        phone: request.phone.clone(),
        theme: request.theme.clone(),
        purpose_type: request.purpose_type,
        joiner_num: request.joiner_num,
        activity_content: request.activity_content.clone(),
        joiners: request.joiners.clone(),
        is_philosophy_social_sciences: request.is_philosophy_social_sciences,
        is_off_school_joiner: request.is_off_school_joiner,
    }
}

// 取消会丢弃正在等待学校结果的 Future；只收尾本机影响，不重放学校请求。
struct CommandEffects {
    cache: Option<core::OfflineCache>,
    observation: std::sync::Arc<core::WriteBoundaryObservation>,
    route: core::ConnectionMode,
    impact: core::CacheInvalidation,
    hint: Option<String>,
    finished: bool,
}
impl Drop for CommandEffects {
    fn drop(&mut self) {
        if self.finished {
            return;
        }
        if let Some(cache) = &self.cache {
            if self.observation.may_have_been_sent() {
                let _ = cache.invalidate(self.route, &self.impact);
            } else if let Some(id) = &self.hint {
                let _ = cache.dismiss_write_readback(id);
            }
        }
    }
}
