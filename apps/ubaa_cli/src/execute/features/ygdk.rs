//! 阳光打卡 handler。

use std::collections::HashMap;

use crate::io::schema::CliFeature;
use serde::Serialize;
use ubaa_core::facade::{
    ActionEligibility, ErrorCode, ErrorKind, FeatureResult, Result, Routed, RoutedError,
    RoutedResult, UbaaError, YgdkClockinSubmitResult, YgdkOverview, YgdkRecord, YgdkRecordsPage,
};

use crate::backend::{CliBackend, RoutedCliBackend};
use crate::command::{YgdkArgs, YgdkCommand};
use crate::execute::routed_readonly;
use crate::io::input::{build_ygdk_request, invalid_input};
use crate::io::schema::{CommandOutput, readonly};

pub(in crate::execute) async fn run_ygdk<B: CliBackend + Send>(
    arguments: YgdkArgs,
    backend: &mut B,
) -> Result<CommandOutput> {
    match arguments.command {
        YgdkCommand::Overview => backend
            .ygdk_overview()
            .await
            .map(|mut result| {
                result.data = safe_overview(result.data);
                result
            })
            .and_then(|data| readonly(data, CliFeature::Ygdk)),
        YgdkCommand::Records { page, size } => backend
            .ygdk_records(page, size)
            .await
            .map(|result| FeatureResult {
                data: safe_records(result.data),
                resolved_route: result.resolved_route,
            })
            .and_then(|data| readonly(data, CliFeature::Ygdk)),
        YgdkCommand::Submit {
            classify_id,
            item_id,
            start_time,
            end_time,
            place,
            photo,
            share_to_square,
            confirm_write,
        } => {
            if confirm_write {
                let request = build_ygdk_request(
                    classify_id,
                    item_id,
                    start_time,
                    end_time,
                    place,
                    &photo,
                    share_to_square,
                )?;
                let result = backend
                    .ygdk_submit(request)
                    .await
                    .map_err(sanitize_submit_error)
                    .and_then(|result| {
                        Ok(FeatureResult {
                            data: safe_submit_receipt(&result.data)?,
                            resolved_route: result.resolved_route,
                        })
                    });
                let readback_route = match &result {
                    Ok(result) => Some(result.resolved_route),
                    Err(error) if error.code == ErrorCode::OutcomeUnknown => Some(backend.mode()),
                    _ => None,
                };
                if let Some(route) = readback_route {
                    best_effort_fixed_readback(backend, route).await;
                }
                result.and_then(|data| readonly(data, CliFeature::Ygdk))
            } else {
                Err(invalid_input("打卡是写操作，必须显式指定 --confirm-write"))
            }
        }
    }
}

pub(in crate::execute) async fn run_routed_ygdk<B: RoutedCliBackend + Send>(
    arguments: YgdkArgs,
    backend: &mut B,
) -> RoutedResult<CommandOutput> {
    match arguments.command {
        YgdkCommand::Overview => routed_readonly(
            backend.ygdk_overview().await.map(|mut result| {
                result.data = safe_overview(result.data);
                result
            }),
            CliFeature::Ygdk,
        ),
        YgdkCommand::Records { page, size } => routed_readonly(
            backend
                .ygdk_records(page, size)
                .await
                .map(|Routed { data, resolution }| Routed {
                    data: safe_records(data),
                    resolution,
                }),
            CliFeature::Ygdk,
        ),
        YgdkCommand::Submit {
            classify_id,
            item_id,
            start_time,
            end_time,
            place,
            photo,
            share_to_square,
            confirm_write,
        } => {
            let result = if confirm_write {
                match build_ygdk_request(
                    classify_id,
                    item_id,
                    start_time,
                    end_time,
                    place,
                    &photo,
                    share_to_square,
                ) {
                    Ok(request) => backend
                        .ygdk_submit(request)
                        .await
                        .map_err(sanitize_routed_submit_error)
                        .and_then(|Routed { data, resolution }| {
                            safe_submit_receipt(&data)
                                .map(|data| Routed { data, resolution })
                                .map_err(|error| RoutedError {
                                    error,
                                    resolution: Some(resolution),
                                })
                        }),
                    Err(error) => Err(RoutedError {
                        error,
                        resolution: None,
                    }),
                }
            } else {
                Err(RoutedError {
                    error: invalid_input("打卡是写操作，必须显式指定 --confirm-write"),
                    resolution: None,
                })
            };
            let readback_route = match &result {
                Ok(result) => Some(result.resolution.mode),
                Err(error) if error.error.code == ErrorCode::OutcomeUnknown => {
                    error.resolution.as_ref().map(|value| value.mode)
                }
                _ => None,
            };
            if let Some(route) = readback_route {
                best_effort_routed_readback(backend, route).await;
            }
            routed_readonly(result, CliFeature::Ygdk)
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct YgdkSubmitReceipt {
    success: bool,
    message: &'static str,
    record_id: Option<i32>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CliYgdkRecord {
    record_id: i32,
    item_id: Option<i32>,
    item_name: Option<String>,
    start_time: Option<String>,
    end_time: Option<String>,
    place: Option<String>,
    image_count: i32,
    is_open: bool,
    state: Option<i32>,
    created_at: Option<String>,
    created_at_label: Option<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CliYgdkRecordsPage {
    content: Vec<CliYgdkRecord>,
    total: i32,
    page: i32,
    size: i32,
    has_more: bool,
}

fn safe_records(page: YgdkRecordsPage) -> CliYgdkRecordsPage {
    CliYgdkRecordsPage {
        content: page.content.into_iter().map(safe_record).collect(),
        total: page.total,
        page: page.page,
        size: page.size,
        has_more: page.has_more,
    }
}

fn safe_record(record: YgdkRecord) -> CliYgdkRecord {
    CliYgdkRecord {
        record_id: record.record_id,
        item_id: record.item_id,
        item_name: record.item_name,
        start_time: record.start_time,
        end_time: record.end_time,
        place: record.place,
        image_count: i32::try_from(record.images.len()).unwrap_or(i32::MAX),
        is_open: record.is_open,
        state: record.state,
        created_at: record.created_at,
        created_at_label: record.created_at_label,
    }
}

fn safe_submit_receipt(result: &YgdkClockinSubmitResult) -> Result<YgdkSubmitReceipt> {
    if !result.success {
        return Err(submit_authority_error());
    }
    Ok(YgdkSubmitReceipt {
        success: true,
        message: "阳光打卡已提交",
        record_id: result.record_id.filter(|record_id| *record_id > 0),
    })
}

fn safe_overview(mut overview: YgdkOverview) -> YgdkOverview {
    let mut item_id_counts = HashMap::new();
    for item in &overview.items {
        *item_id_counts.entry(item.item_id).or_insert(0_usize) += 1;
    }
    for item in &mut overview.items {
        let target_is_valid = item.submit_eligibility == ActionEligibility::Allowed
            && overview.classify_id > 0
            && !overview.classify_name.trim().is_empty()
            && item.item_id > 0
            && !item.name.trim().is_empty()
            && item_id_counts.get(&item.item_id) == Some(&1)
            && item.submit_target.is_some_and(|target| {
                target.classify_id == overview.classify_id && target.item_id == item.item_id
            });
        let target_is_contradictory = (item.submit_eligibility == ActionEligibility::Allowed
            && !target_is_valid)
            || (item.submit_eligibility != ActionEligibility::Allowed
                && item.submit_target.is_some());
        if target_is_contradictory {
            item.submit_eligibility = ActionEligibility::Unknown;
            item.submit_target = None;
        }
    }
    overview
}

fn sanitize_submit_error(error: UbaaError) -> UbaaError {
    match error.code {
        ErrorCode::OutcomeUnknown => UbaaError::new(
            ErrorCode::OutcomeUnknown,
            ErrorKind::Upstream,
            false,
            "阳光打卡提交结果未知，请刷新概览与记录核对后再操作",
        ),
        ErrorCode::UpstreamChanged => submit_authority_error(),
        _ => error,
    }
}

fn sanitize_routed_submit_error(mut error: RoutedError) -> RoutedError {
    error.error = sanitize_submit_error(error.error);
    error
}

fn submit_authority_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "阳光打卡提交资格核对响应无效",
    )
}

async fn best_effort_fixed_readback<B: CliBackend + Send>(
    backend: &mut B,
    route: ubaa_core::facade::ConnectionMode,
) {
    let _overview = backend.ygdk_overview_on_route(route).await;
    let _records = backend.ygdk_records_on_route(route, 1, 20).await;
}

async fn best_effort_routed_readback<B: RoutedCliBackend + Send>(
    backend: &mut B,
    route: ubaa_core::facade::ConnectionMode,
) {
    let _overview = backend.ygdk_overview_on_route(route).await;
    let _records = backend.ygdk_records_on_route(route, 1, 20).await;
}
