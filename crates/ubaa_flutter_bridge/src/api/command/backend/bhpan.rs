use super::{CommandBackend, core, disposed_error, routed_bridge_error};
use futures_util::FutureExt;
use std::sync::{Arc, atomic::Ordering};

pub(super) async fn execute(
    backend: &mut CommandBackend<'_>,
    args: &ubaa_command::BhpanArgs,
    input: &ubaa_command::bhpan::BhpanPreparedInput,
) -> core::RoutedResult<ubaa_command::bhpan::BhpanOutput> {
    let mut guard = backend.client.inner.lock().await;
    if backend.client.is_disposed.load(Ordering::SeqCst) {
        return Err(routed_bridge_error(disposed_error()));
    }
    let client = guard
        .as_mut()
        .ok_or_else(|| routed_bridge_error(disposed_error()))?;
    let resolution = client.resolve_bhpan_route()?.resolution;
    let observation = Arc::new(client.observe_write_boundary());
    if let Some(command) = backend.command {
        command.control.check().map_err(|_| core::RoutedError {
            error: super::internal_error("命令已停止"),
            resolution: Some(resolution),
        })?;
        *command.sent.lock().unwrap() = Some((observation.clone(), resolution));
    }
    std::panic::AssertUnwindSafe(ubaa_command::bhpan::execute_bhpan(client, args, input))
        .catch_unwind()
        .await
        .unwrap_or_else(|_| {
            Err(core::RoutedError {
                error: core::UbaaError::new(
                    if observation.may_have_been_sent() {
                        core::ErrorCode::OutcomeUnknown
                    } else {
                        core::ErrorCode::InternalError
                    },
                    core::ErrorKind::Internal,
                    false,
                    "云盘操作未取得可确认结果，请先只读核对",
                ),
                resolution: Some(resolution),
            })
        })
}
