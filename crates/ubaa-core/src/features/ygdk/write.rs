//! 阳光打卡照片上传后的显式打卡提交。

use crate::domain::{YgdkClockinSubmitRequest, YgdkClockinSubmitResult};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;

use super::auth::ensure_login;
use super::http::post;
use super::parser::{error, integer, parse_envelope};
use super::read::get_overview;
use super::upload::upload_photo;

/// 上传照片并提交打卡。该操作只由显式确认的宿主调用，实时验证器不会调用。
pub(crate) async fn submit_clockin(
    runtime: &mut ClientRuntime,
    request: YgdkClockinSubmitRequest,
) -> Result<YgdkClockinSubmitResult> {
    let photo = request.photo.as_ref().ok_or_else(|| {
        UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "打卡照片不能为空",
        )
    })?;
    if photo.bytes.is_empty() {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "打卡照片不能为空",
        ));
    }
    if request.start_time.is_none() || request.end_time.is_none() {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "开始和结束时间必须同时提供",
        ));
    }
    let credential = ensure_login(runtime).await?;
    let overview = get_overview(runtime).await?;
    let item = request
        .item_id
        .map_or_else(
            || {
                overview
                    .items
                    .iter()
                    .find(|item| item.name.contains('跑'))
                    .or_else(|| overview.items.first())
            },
            |id| overview.items.iter().find(|item| item.item_id == id),
        )
        .ok_or_else(|| error("未找到阳光打卡项目"))?;
    let photo = request.photo.expect("validated photo");
    let file_name = upload_photo(runtime, &credential, &photo).await?;
    let (start, end) = request.start_time.zip(request.end_time).ok_or_else(|| {
        UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "开始和结束时间必须同时提供",
        )
    })?;
    let place = request
        .place
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| "操场".into());
    let params = [
        ("start_time", start.clone()),
        ("end_time", end.clone()),
        ("place_type", "1".into()),
        ("place", place),
        (
            "isopen",
            if request.share_to_square.unwrap_or(false) {
                "1"
            } else {
                "0"
            }
            .into(),
        ),
        ("form_time_fmt", format!("{start}-{end}")),
        ("images", serde_json::json!([file_name]).to_string()),
        ("classify_id", overview.classify_id.to_string()),
        ("item_id", item.item_id.to_string()),
        ("item_name", item.name.clone()),
    ];
    let body = post(
        runtime,
        "/api/Front/Clockin/Clockin/clockin",
        &credential,
        &params,
    )
    .await?;
    let result = parse_envelope(&body)?;
    let object = result
        .as_object()
        .ok_or_else(|| error("阳光打卡提交响应无效"))?;
    Ok(YgdkClockinSubmitResult {
        success: true,
        message: "打卡成功".into(),
        record_id: integer(object, "record_id"),
        summary: None,
    })
}
