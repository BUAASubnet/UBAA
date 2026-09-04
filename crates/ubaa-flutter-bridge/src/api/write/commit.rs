//! 一次性写入意图的消费、提交前复核与 Core 写分派。

use super::support::{
    ensure_bykc_course_target, ensure_bykc_deselect_allowed, ensure_bykc_preflight_route,
    ensure_bykc_select_allowed, invalid_input, map_cgyy_request, map_commit_error,
    map_evaluation_course, map_resolution_error, now_seconds, safe_message,
};
use super::{BridgeWriteCommitResult, PendingWrite};
use crate::api::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeErrorCode, BridgeErrorKind, catch_panic,
    disposed_error,
};
use crate::api::read::map_cgyy_order;
use ubaa_core::facade as domain;

impl BridgeClient {
    pub async fn commit_write(
        &self,
        intent_id: String,
    ) -> Result<BridgeWriteCommitResult, BridgeError> {
        catch_panic(async {
            if intent_id.trim().is_empty() {
                return Err(invalid_input("intent id is required"));
            }
            // 所有会清理写意图的路径都先持有 Core 锁；这样重新登录或重开路线
            // 不会在本次提交等待 Core 锁时失效后，仍让旧意图继续执行。
            let mut guard = self.inner.lock().await;
            let entry = {
                let mut intents = self.write_intents.lock().await;
                intents.remove(&intent_id).ok_or_else(|| {
                    BridgeError::local(
                        BridgeErrorCode::IntentExpired,
                        BridgeErrorKind::Input,
                        false,
                        "write intent is expired or already used",
                    )
                })?
            };
            if now_seconds() >= entry.expires_at {
                return Err(BridgeError::local(
                    BridgeErrorCode::IntentExpired,
                    BridgeErrorKind::Input,
                    false,
                    "write intent is expired",
                ));
            }
            let pending = entry.request;
            let operation = pending.operation();
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let current_resolution = client
                .resolve_route_for_feature(pending.feature())
                .map_err(map_resolution_error)?;
            let current_route: BridgeConnectionMode = current_resolution.mode.into();
            if current_route != entry.resolved_route {
                return Err(BridgeError::local(
                    BridgeErrorCode::OperationConflict,
                    BridgeErrorKind::Input,
                    true,
                    "route changed; prepare the write again",
                ));
            }
            match &pending {
                PendingWrite::BykcSelect(request) => {
                    let current = client
                        .bykc_course_detail(request.course_id)
                        .await
                        .map_err(BridgeError::from_routed)?;
                    ensure_bykc_course_target(request.course_id, current.data.id)?;
                    ensure_bykc_preflight_route(
                        entry.resolved_route,
                        current.resolution.mode.into(),
                    )?;
                    ensure_bykc_select_allowed(current.data.select_eligibility)?;
                }
                PendingWrite::BykcDeselect(request) => {
                    let current = client
                        .bykc_course_detail(request.course_id)
                        .await
                        .map_err(BridgeError::from_routed)?;
                    ensure_bykc_course_target(request.course_id, current.data.id)?;
                    ensure_bykc_preflight_route(
                        entry.resolved_route,
                        current.resolution.mode.into(),
                    )?;
                    ensure_bykc_deselect_allowed(current.data.deselect_eligibility)?;
                }
                _ => {}
            }
            let result = match pending {
                PendingWrite::BykcSelect(request) => client
                    .bykc_select_course(request.course_id)
                    .await
                    .map(|r| (r.resolution, safe_message("博雅选课已提交"), None)),
                PendingWrite::BykcDeselect(request) => client
                    .bykc_deselect_course(request.course_id)
                    .await
                    .map(|r| (r.resolution, safe_message("博雅退选已提交"), None)),
                PendingWrite::BykcSign(request) => {
                    let message = if request.sign_type == 1 {
                        "博雅签到已提交"
                    } else {
                        "博雅签退已提交"
                    };
                    client
                        .bykc_sign_course(domain::BykcSignRequest {
                            course_id: request.course_id,
                            lat: request.lat,
                            lng: request.lng,
                            sign_type: request.sign_type,
                        })
                        .await
                        .map(|r| (r.resolution, safe_message(message), None))
                }
                PendingWrite::Signin(request) => client
                    .signin_perform(&request.course_id)
                    .await
                    .map(|r| (r.resolution, safe_message("课堂签到已提交"), None)),
                PendingWrite::LibbookReserve(request) => client
                    .libbook_reserve(domain::LibBookReserveRequest {
                        area_id: request.area_id,
                        seat_id: request.seat_id,
                        day: request.day,
                        segment: request.segment,
                        start_time: request.start_time,
                        end_time: request.end_time,
                    })
                    .await
                    .map(|r| (r.resolution, safe_message("图书馆预约已提交"), None)),
                PendingWrite::LibbookCancel(request) => client
                    .libbook_cancel_booking(&request.id)
                    .await
                    .map(|r| (r.resolution, safe_message("图书馆预约已取消"), None)),
                PendingWrite::Ygdk(request) => client
                    .ygdk_submit(domain::YgdkClockinSubmitRequest {
                        item_id: request.item_id,
                        start_time: request.start_time,
                        end_time: request.end_time,
                        place: request.place,
                        share_to_square: request.share_to_square,
                        photo: request.photo.map(|p| domain::YgdkPhotoUpload {
                            bytes: p.bytes,
                            file_name: p.file_name,
                            mime_type: p.mime_type,
                        }),
                    })
                    .await
                    .map(|r| (r.resolution, safe_message("阳光打卡已提交"), None)),
                PendingWrite::CgyyReserve(request) => client
                    .cgyy_submit_reservation(map_cgyy_request(request))
                    .await
                    .map(|r| {
                        (
                            r.resolution,
                            safe_message("场馆预约已提交"),
                            r.data.order.map(map_cgyy_order),
                        )
                    }),
                PendingWrite::CgyyCancel(request) => client
                    .cgyy_cancel_order(request.id)
                    .await
                    .map(|r| (r.resolution, safe_message("场馆订单已取消"), None)),
                PendingWrite::Evaluation(request) => client
                    .evaluation_submit_courses(
                        request
                            .courses
                            .into_iter()
                            .map(map_evaluation_course)
                            .collect(),
                    )
                    .await
                    .map(|r| (r.resolution, safe_message("教学评教已提交"), None)),
            };
            match result {
                Ok((resolution, message, order)) => Ok(BridgeWriteCommitResult {
                    operation,
                    success: true,
                    message,
                    outcome_unknown: false,
                    resolved_route: Some(resolution.mode.into()),
                    order,
                }),
                Err(error) => Err(map_commit_error(operation, error)),
            }
        })
        .await
    }
}
