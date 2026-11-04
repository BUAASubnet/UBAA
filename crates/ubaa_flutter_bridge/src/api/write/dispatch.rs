//! GUI 与命令共用一次性载荷的 fresh commit，原始 typed 回执留给各自展示层。
use super::support::{map_cgyy_receipt, map_evaluation_batch, map_ygdk_receipt, safe_message};
use super::{BridgeWriteOperation, PendingWrite};
use ubaa_core::facade as core;

#[derive(Clone)]
pub(crate) enum WriteReceipt {
    Bykc(core::BykcActionResult),
    BykcSign(core::BykcActionResult, i32),
    Signin(core::SigninActionResult),
    LibbookReserve(core::LibBookReserveResult),
    LibbookCancel(core::LibBookCancelResult),
    Ygdk(core::YgdkClockinSubmitResult),
    CgyyReserve(core::CgyyReservationResult),
    CgyyCancel(core::CgyyCancelOrderResult),
    Evaluation(core::EvaluationBatchResult),
}
pub(crate) async fn dispatch(
    client: &mut core::UbaaClient,
    pending: PendingWrite,
    route: core::ConnectionMode,
) -> core::RoutedResult<WriteReceipt> {
    macro_rules! receipt {
        ($call:expr,$variant:ident) => {
            $call.await.map(|r| core::Routed {
                data: WriteReceipt::$variant(r.data),
                resolution: r.resolution,
            })
        };
    }
    match pending {
        PendingWrite::BykcSelect(v) => receipt!(
            client.bykc_select_course_if_route_matches(v.course_id, route),
            Bykc
        ),
        PendingWrite::BykcDeselect(v) => receipt!(
            client.bykc_deselect_course_if_route_matches(v.course_id, route),
            Bykc
        ),
        PendingWrite::BykcSign(v) => client
            .bykc_sign_course_if_route_matches(
                core::BykcSignRequest {
                    course_id: v.course_id,
                    lat: v.lat,
                    lng: v.lng,
                    sign_type: v.sign_type,
                },
                route,
            )
            .await
            .map(|r| core::Routed {
                data: WriteReceipt::BykcSign(r.data, v.sign_type),
                resolution: r.resolution,
            }),
        PendingWrite::Signin(v) => receipt!(
            client.signin_perform_if_route_matches(&v.course_id, route),
            Signin
        ),
        PendingWrite::LibbookReserve(v) => receipt!(
            client.libbook_reserve_if_route_matches(
                core::LibBookReserveRequest {
                    area_id: v.area_id,
                    seat_id: v.seat_id,
                    day: v.day,
                    segment: v.segment,
                    start_time: v.start_time,
                    end_time: v.end_time
                },
                route
            ),
            LibbookReserve
        ),
        PendingWrite::LibbookCancel(v) => receipt!(
            client.libbook_cancel_booking_if_route_matches(
                core::LibBookCancelRequest {
                    booking_id: v.id,
                    page: v.page,
                    limit: v.limit
                },
                route
            ),
            LibbookCancel
        ),
        PendingWrite::Ygdk(v) => receipt!(client.ygdk_submit_if_route_matches(v, route), Ygdk),
        PendingWrite::CgyyReserve(v) => receipt!(
            client.cgyy_submit_reservation_if_route_matches(v, route),
            CgyyReserve
        ),
        PendingWrite::CgyyCancel(v) => receipt!(
            client.cgyy_cancel_order_if_route_matches(
                core::CgyyCancelOrderRequest {
                    order_id: v.order_id
                },
                route
            ),
            CgyyCancel
        ),
        PendingWrite::Evaluation(v) => receipt!(
            client.evaluation_submit_courses_if_route_matches(v, route),
            Evaluation
        ),
    }
}
pub(crate) type Projection = (
    core::RouteResolution,
    bool,
    String,
    Option<super::BridgeCgyyReservationReceipt>,
    Option<super::BridgeYgdkSubmitReceipt>,
    Option<super::BridgeEvaluationBatchResult>,
);
pub(crate) fn project(
    value: core::Routed<WriteReceipt>,
    operation: BridgeWriteOperation,
) -> Projection {
    let (success, message, cgyy, ygdk, evaluation) = match value.data {
        WriteReceipt::Bykc(_) => (
            true,
            safe_message(match operation {
                BridgeWriteOperation::BykcSelectCourse => "博雅选课已提交",
                BridgeWriteOperation::BykcDeselectCourse => "博雅退选已提交",
                _ => "博雅签到已提交",
            }),
            None,
            None,
            None,
        ),
        WriteReceipt::BykcSign(_, kind) => (
            true,
            safe_message(if kind == 1 {
                "博雅签到已提交"
            } else {
                "博雅签退已提交"
            }),
            None,
            None,
            None,
        ),
        WriteReceipt::Signin(v) => (
            v.success,
            safe_message(if v.success {
                "签到成功"
            } else {
                "签到未完成"
            }),
            None,
            None,
            None,
        ),
        WriteReceipt::LibbookReserve(v) => (
            v.success,
            safe_message(if v.success {
                "图书馆预约已提交"
            } else {
                "图书馆预约未完成"
            }),
            None,
            None,
            None,
        ),
        WriteReceipt::LibbookCancel(v) => (
            v.success,
            safe_message(if v.success {
                "图书馆预约已取消"
            } else {
                "图书馆预约取消未完成"
            }),
            None,
            None,
            None,
        ),
        WriteReceipt::Ygdk(v) => (
            v.success,
            safe_message("阳光打卡已提交"),
            None,
            map_ygdk_receipt(v.record_id),
            None,
        ),
        WriteReceipt::CgyyReserve(v) => (
            v.success,
            safe_message(if v.success {
                "研讨室预约已提交"
            } else {
                "研讨室预约未完成"
            }),
            v.receipt.map(map_cgyy_receipt),
            None,
            None,
        ),
        WriteReceipt::CgyyCancel(v) => (
            v.success,
            safe_message(if v.success {
                "研讨室订单已取消"
            } else {
                "研讨室订单取消未完成"
            }),
            None,
            None,
            None,
        ),
        WriteReceipt::Evaluation(v) => {
            let batch = map_evaluation_batch(v);
            (
                batch.success,
                safe_message(super::commit::evaluation_commit_message(&batch)),
                None,
                None,
                Some(batch),
            )
        }
    };
    (value.resolution, success, message, cgyy, ygdk, evaluation)
}
