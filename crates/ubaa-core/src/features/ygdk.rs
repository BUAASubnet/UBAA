//! 阳光打卡只读响应解析与业务查询。
#![allow(clippy::missing_errors_doc)]

use crate::domain::{
    YgdkClockinSubmitRequest, YgdkClockinSubmitResult, YgdkItem, YgdkOverview, YgdkRecord,
    YgdkRecordsPage, YgdkTermSummary,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use chrono::{FixedOffset, TimeZone};
use serde_json::{Map, Value};

use super::ygdk_upload::build_upload_body;

pub(crate) use crate::internal::route_state::YgdkCredential;

const FRONT_BASE: &str = "https://ygdk.buaa.edu.cn";
const EMPTY_SUCCESS_ENVELOPE: &str = r#"{"code":1,"result":{}}"#;
const OAUTH_URL: &str = "https://app.buaa.edu.cn/uc/api/oauth/index?redirect=https%3A%2F%2Fygdk.buaa.edu.cn%2F%23%2Fhome&appid=200230221144501510&state=STATE&qrcode=1";
const LOGIN_URL: &str = "https://ygdk.buaa.edu.cn/api/Front/Clockin/User/campusAppLogin";
const REDIRECT_LIMIT: usize = 10;

fn error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}
fn integer(map: &Map<String, Value>, key: &str) -> Option<i32> {
    map.get(key)
        .and_then(Value::as_i64)
        .and_then(|v| i32::try_from(v).ok())
        .or_else(|| {
            map.get(key)
                .and_then(Value::as_str)
                .and_then(|v| v.parse().ok())
        })
}
fn string(map: &Map<String, Value>, key: &str) -> Option<String> {
    map.get(key)
        .and_then(|value| match value {
            Value::String(value) => Some(value.clone()),
            Value::Number(value) => Some(value.to_string()),
            Value::Bool(value) => Some(value.to_string()),
            _ => None,
        })
        .filter(|v| !v.trim().is_empty())
}

fn datetime_text(map: &Map<String, Value>, key: &str) -> Option<String> {
    if let Some(value) = string(map, key) {
        if let Ok(seconds) = value.trim().parse::<i64>() {
            return FixedOffset::east_opt(8 * 60 * 60)?
                .timestamp_opt(seconds, 0)
                .single()
                .map(|value| value.format("%Y-%m-%d %H:%M").to_string());
        }
        return Some(value);
    }
    let seconds = map.get(key).and_then(Value::as_i64)?;
    FixedOffset::east_opt(8 * 60 * 60)?
        .timestamp_opt(seconds, 0)
        .single()
        .map(|value| value.format("%Y-%m-%d %H:%M").to_string())
}
fn list(map: &Map<String, Value>, key: &str) -> Vec<Value> {
    map.get(key)
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
}

/// 解析旧版响应包装，`code=1` 表示业务成功。
pub fn parse_envelope(body: &str) -> Result<Value> {
    let payload: Value = serde_json::from_str(body).map_err(|_| error("阳光打卡响应无法解析"))?;
    let object = payload
        .as_object()
        .ok_or_else(|| error("阳光打卡响应结构无效"))?;
    match integer(object, "code") {
        Some(1) => Ok(object.get("result").cloned().unwrap_or(Value::Null)),
        Some(-98) => Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "阳光打卡业务会话已失效",
        )),
        _ => Err(error(
            string(object, "msg")
                .as_deref()
                .unwrap_or("阳光打卡请求失败"),
        )),
    }
}

pub fn parse_overview(
    classify: &str,
    items: &str,
    count: &str,
    term: &str,
) -> Result<YgdkOverview> {
    let classify = parse_envelope(classify)?;
    let classifies = classify
        .as_object()
        .map(|v| list(v, "list"))
        .unwrap_or_default();
    let selected = classifies
        .iter()
        .filter_map(Value::as_object)
        .find(|v| string(v, "name").is_some_and(|n| n.contains("体育")))
        .cloned()
        .or_else(|| classifies_fallback(&classify))
        .ok_or_else(|| error("未获取到阳光打卡分类"))?;
    let classify_id =
        integer(&selected, "classify_id").ok_or_else(|| error("阳光打卡分类缺少标识"))?;
    let classify_name = string(&selected, "name").ok_or_else(|| error("阳光打卡分类缺少名称"))?;
    let parsed_items = parse_items(items)?;
    let default = parsed_items
        .iter()
        .find(|v| v.name.contains('跑'))
        .or_else(|| {
            parsed_items
                .iter()
                .min_by_key(|v| v.sort.unwrap_or(i32::MAX))
        })
        .ok_or_else(|| error("未获取到阳光打卡项目列表"))?;
    let count = parse_envelope(count)?
        .as_object()
        .cloned()
        .unwrap_or_default();
    let term = parse_envelope(term)?
        .as_object()
        .cloned()
        .unwrap_or_default();
    Ok(YgdkOverview {
        summary: YgdkTermSummary {
            term_id: integer(&term, "term_id").or_else(|| integer(&term, "id")),
            term_name: string(&term, "name"),
            term_count: integer(&count, "term_good_count_show")
                .or_else(|| integer(&count, "term_good_count"))
                .or_else(|| integer(&count, "term_count_show"))
                .or_else(|| integer(&count, "term_count"))
                .unwrap_or(0),
            term_target: integer(&count, "term_num").or_else(|| integer(&selected, "term_num")),
            week_count: integer(&count, "week_count"),
            week_target: integer(&count, "week_num").or_else(|| integer(&selected, "week_num")),
            month_count: integer(&count, "month_count"),
            month_target: integer(&count, "month_num").or_else(|| integer(&selected, "month_num")),
            day_count: integer(&count, "day_count"),
            good_count: integer(&count, "term_good_count_show")
                .or_else(|| integer(&count, "term_good_count")),
        },
        classify_id,
        classify_name,
        default_item_id: default.item_id,
        default_item_name: default.name.clone(),
        items: parsed_items,
    })
}
fn classifies_fallback(value: &Value) -> Option<Map<String, Value>> {
    value
        .as_object()?
        .get("list")?
        .as_array()?
        .iter()
        .find_map(|v| v.as_object().cloned())
        .filter(|v| integer(v, "classify_id") == Some(1))
        .or_else(|| {
            value
                .as_object()?
                .get("list")?
                .as_array()?
                .iter()
                .find_map(|v| v.as_object().cloned())
        })
}
pub fn parse_items(body: &str) -> Result<Vec<YgdkItem>> {
    let result = parse_envelope(body)?;
    Ok(result
        .as_object()
        .map(|v| list(v, "list"))
        .unwrap_or_default()
        .into_iter()
        .filter_map(|v| {
            let o = v.as_object()?;
            Some(YgdkItem {
                item_id: integer(o, "item_id")?,
                name: string(o, "name")?,
                kind: integer(o, "type"),
                sort: integer(o, "sort"),
            })
        })
        .collect())
}
pub fn parse_records(
    body: &str,
    items: &[YgdkItem],
    page: i32,
    size: i32,
) -> Result<YgdkRecordsPage> {
    if page <= 0 || size <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "分页参数无效",
        ));
    }
    let result = parse_envelope(body)?;
    let object = result
        .as_object()
        .ok_or_else(|| error("阳光打卡记录结构无效"))?;
    let content = list(object, "list")
        .into_iter()
        .filter_map(|v| {
            let o = v.as_object()?;
            let item_id = integer(o, "item_id");
            let raw = o.get("images_fmt").or_else(|| o.get("images"));
            let images = match raw {
                Some(Value::Array(v)) => v
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect(),
                Some(Value::String(v)) => {
                    if v.trim().is_empty() {
                        vec![]
                    } else {
                        serde_json::from_str::<Vec<String>>(v)
                            .unwrap_or_else(|_| vec![v.to_owned()])
                    }
                }
                _ => vec![],
            };
            Some(YgdkRecord {
                record_id: integer(o, "record_id")?,
                item_id,
                item_name: string(o, "item_name").or_else(|| {
                    item_id.and_then(|id| {
                        items
                            .iter()
                            .find(|v| v.item_id == id)
                            .map(|v| v.name.clone())
                    })
                }),
                start_time: datetime_text(o, "start_time"),
                end_time: datetime_text(o, "end_time"),
                place: string(o, "place"),
                images,
                is_open: integer(o, "isopen") == Some(1),
                state: integer(o, "state"),
                created_at: string(o, "create_time_fmt"),
                created_at_label: string(o, "create_time_fmt"),
            })
        })
        .collect();
    let total = integer(object, "total").unwrap_or(0);
    Ok(YgdkRecordsPage {
        content,
        total,
        page,
        size,
        has_more: page.saturating_mul(size) < total,
    })
}

/// 查询阳光打卡概览，按旧版顺序组合分类、项目、统计和学期接口。
pub(crate) async fn get_overview(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<YgdkOverview> {
    match get_overview_once(runtime).await {
        Err(error) if error.code == ErrorCode::AuthenticationRequired => {
            runtime.feature_state().ygdk.clear();
            get_overview_once(runtime).await
        }
        result => result,
    }
}

async fn get_overview_once(runtime: &mut crate::runtime::ClientRuntime) -> Result<YgdkOverview> {
    let credential = ensure_login(runtime).await?;
    let classify = post(
        runtime,
        "/api/Front/Clockin/Classify/getList",
        &credential,
        &[],
    )
    .await?;
    let classifies = parse_envelope(&classify)?;
    let selected = classifies
        .as_object()
        .and_then(|v| {
            list(v, "list").into_iter().find_map(|v| {
                let o = v.as_object()?.clone();
                (string(&o, "name").is_some_and(|n| n.contains("体育"))).then_some(o)
            })
        })
        .or_else(|| classifies_fallback(&classifies))
        .ok_or_else(|| error("未获取到阳光打卡分类"))?;
    let classify_id =
        integer(&selected, "classify_id").ok_or_else(|| error("阳光打卡分类缺少标识"))?;
    let query = [
        ("page", "1".to_owned()),
        ("limit", "1000".to_owned()),
        ("classify_id", classify_id.to_string()),
    ];
    let items = post_with_query(
        runtime,
        "/api/Front/Clockin/Item/getList",
        &credential,
        &query,
    )
    .await?;
    let count = optional_success_response(
        post(
            runtime,
            "/api/Front/Clockin/Clockin/getCount",
            &credential,
            &[
                ("classify_id", classify_id.to_string()),
                ("user_id", credential.uid.to_string()),
            ],
        )
        .await,
    );
    let term = optional_success_response(
        post(runtime, "/api/Front/Clockin/Term/get", &credential, &[]).await,
    );
    parse_overview(&classify, &items, &count, &term)
}

fn optional_success_response(response: Result<String>) -> String {
    match response {
        Ok(body) if parse_envelope(&body).is_ok() => body,
        _ => EMPTY_SUCCESS_ENVELOPE.to_owned(),
    }
}

/// 查询阳光打卡历史记录。
pub(crate) async fn get_records(
    runtime: &mut crate::runtime::ClientRuntime,
    page: i32,
    size: i32,
) -> Result<YgdkRecordsPage> {
    if page <= 0 || size <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "分页参数无效",
        ));
    }
    let credential = ensure_login(runtime).await?;
    let overview = get_overview(runtime).await?;
    let params = [
        ("page", page.to_string()),
        ("limit", size.to_string()),
        ("classify_id", overview.classify_id.to_string()),
        ("user_id", credential.uid.to_string()),
    ];
    let body = post_with_query(
        runtime,
        "/api/Front/Clockin/Clockin/getList",
        &credential,
        &params,
    )
    .await?;
    parse_records(&body, &overview.items, page, size)
}

/// 上传照片并提交打卡。该操作只由显式确认的宿主调用，实时验证器不会调用。
pub(crate) async fn submit_clockin(
    runtime: &mut crate::runtime::ClientRuntime,
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

async fn upload_photo(
    runtime: &mut crate::runtime::ClientRuntime,
    credential: &YgdkCredential,
    photo: &crate::domain::YgdkPhotoUpload,
) -> Result<String> {
    let boundary = "ubaa-ygdk-boundary";
    let body = build_upload_body(credential, photo, boundary);
    let mut request = HttpRequest::post(
        runtime.url(&format!("{FRONT_BASE}/api/Front/Upload/File/post"))?,
        body,
    );
    request.headers.insert(
        "Content-Type".into(),
        format!("multipart/form-data; boundary={boundary}"),
    );
    request
        .headers
        .insert("X-Requested-With".into(), "XMLHttpRequest".into());
    let response = runtime.request(request).await?;
    if response.status != 200 {
        return Err(error("阳光打卡图片上传失败"));
    }
    let value = parse_envelope(&super::body(&response))?;
    value
        .as_object()
        .and_then(|object| string(object, "file_name"))
        .ok_or_else(|| error("阳光打卡图片上传响应无效"))
}

async fn ensure_login(runtime: &mut crate::runtime::ClientRuntime) -> Result<YgdkCredential> {
    super::require_session(runtime)?;
    let state = runtime.feature_state();
    if let Some(value) = state.ygdk.credential() {
        return Ok(value);
    }
    let _guard = state.ygdk.login_guard().await;
    if let Some(value) = state.ygdk.credential() {
        return Ok(value);
    }
    let code = oauth_code(runtime).await?;
    let mut url =
        url::Url::parse(&runtime.url(LOGIN_URL)?).map_err(|_| error("阳光打卡登录地址无效"))?;
    url.query_pairs_mut().append_pair("code", &code);
    let response = runtime.request(HttpRequest::get(url.to_string())).await?;
    if response.status != 200 {
        return Err(error("阳光打卡登录失败"));
    }
    let value = parse_envelope(&super::body(&response))?;
    let data = value
        .get("data")
        .unwrap_or(&value)
        .as_object()
        .ok_or_else(|| error("阳光打卡登录响应无效"))?;
    let uid = integer(data, "uid").ok_or_else(|| error("阳光打卡返回 uid 缺失"))?;
    let token = string(data, "token").ok_or_else(|| error("阳光打卡返回 token 缺失"))?;
    let credential = YgdkCredential {
        uid,
        token: percent_decode(&token),
    };
    state.ygdk.set(credential.clone());
    Ok(credential)
}

async fn oauth_code(runtime: &mut crate::runtime::ClientRuntime) -> Result<String> {
    let mut current = OAUTH_URL.to_owned();
    for _ in 0..REDIRECT_LIMIT {
        let response = runtime
            .request(HttpRequest::get(runtime.url(&current)?))
            .await?;
        if let Some(code) = code_from_url(&response.final_url) {
            return Ok(code);
        }
        let location = response
            .headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("location"))
            .and_then(|(_, v)| v.first())
            .ok_or_else(|| error("阳光打卡登录跳转缺少目标地址"))?;
        let base =
            url::Url::parse(&response.final_url).map_err(|_| error("阳光打卡登录跳转地址无效"))?;
        current = base
            .join(location)
            .map_err(|_| error("阳光打卡登录跳转地址无效"))?
            .to_string();
        if let Some(code) = code_from_url(&current) {
            return Ok(code);
        }
    }
    Err(error("阳光打卡登录跳转次数超限"))
}

fn code_from_url(raw: &str) -> Option<String> {
    let url = url::Url::parse(raw).ok()?;
    url.query_pairs()
        .find(|(k, _)| k == "code")
        .map(|(_, v)| v.into_owned())
        .or_else(|| {
            let query = url.fragment()?.split_once('?')?.1;
            url::form_urlencoded::parse(query.as_bytes())
                .find(|(key, _)| key == "code")
                .map(|(_, value)| value.into_owned())
        })
}

fn percent_decode(value: &str) -> String {
    let encoded = format!("value={value}");
    url::form_urlencoded::parse(encoded.as_bytes())
        .next()
        .map_or_else(|| value.to_owned(), |(_, v)| v.into_owned())
}

async fn post(
    runtime: &mut crate::runtime::ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    params: &[(&str, String)],
) -> Result<String> {
    post_request(runtime, path, credential, params, false).await
}

async fn post_with_query(
    runtime: &mut crate::runtime::ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    params: &[(&str, String)],
) -> Result<String> {
    post_request(runtime, path, credential, params, true).await
}

async fn post_request(
    runtime: &mut crate::runtime::ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    params: &[(&str, String)],
    duplicate_params_in_query: bool,
) -> Result<String> {
    let mut form: Vec<(&str, String)> = params.iter().map(|(k, v)| (*k, v.clone())).collect();
    form.push(("uid", credential.uid.to_string()));
    form.push(("token", credential.token.clone()));
    let body = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs(form.iter().map(|(k, v)| (*k, v.as_str())))
        .finish()
        .into_bytes();
    let mut direct = url::Url::parse(&format!("{FRONT_BASE}{path}"))
        .map_err(|_| error("阳光打卡请求地址无效"))?;
    if duplicate_params_in_query {
        direct
            .query_pairs_mut()
            .extend_pairs(params.iter().map(|(key, value)| (*key, value.as_str())));
    }
    let mut request = HttpRequest::post(runtime.url(direct.as_str())?, body);
    request.headers.insert(
        "Content-Type".into(),
        "application/x-www-form-urlencoded; charset=UTF-8".into(),
    );
    request
        .headers
        .insert("X-Requested-With".into(), "XMLHttpRequest".into());
    let response = runtime.request(request).await?;
    if response.status != 200 {
        return Err(error("阳光打卡服务暂时不可用"));
    }
    Ok(super::body(&response))
}

#[cfg(test)]
mod tests {
    use super::{YgdkCredential, build_upload_body, code_from_url, parse_records, percent_decode};
    use crate::domain::{ConnectionMode, YgdkClockinSubmitRequest, YgdkPhotoUpload};
    use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
    use crate::runtime::ClientRuntime;
    use crate::session::FileSessionStore;
    use async_trait::async_trait;

    #[test]
    fn 从回调片段查询中提取授权码() {
        assert_eq!(
            code_from_url("https://ygdk.buaa.edu.cn/#/home?code=%E5%B7%B2%E8%84%B1%E6%95%8F"),
            Some("已脱敏".into())
        );
    }

    #[test]
    fn 解码不含等号的业务令牌值() {
        assert_eq!(percent_decode("token%2Bvalue%2Ftail"), "token+value/tail");
    }

    #[test]
    fn 阳光打卡凭据调试输出不泄露令牌() {
        let credential = YgdkCredential {
            uid: 42,
            token: "ygdk-secret-token".into(),
        };
        let rendered = format!("{credential:?}");
        assert!(!rendered.contains("ygdk-secret-token"));
    }

    #[test]
    fn 记录时间戳按冻结东八区格式化() {
        let body = serde_json::json!({
            "code": 1,
            "result": {"list": [{"record_id": 1, "start_time": 1_772_323_200, "end_time": 1_772_326_800}]}
        })
        .to_string();
        let page = parse_records(&body, &[], 1, 10).expect("解析记录");
        assert_eq!(
            page.content[0].start_time.as_deref(),
            Some("2026-03-01 08:00")
        );
    }

    #[test]
    fn 数字字符串时间戳同样按冻结格式化() {
        let body = serde_json::json!({
            "code": 1,
            "result": {"list": [{"record_id": 1, "start_time": "1772323200"}]}
        })
        .to_string();
        let page = parse_records(&body, &[], 1, 10).expect("解析记录");
        assert_eq!(
            page.content[0].start_time.as_deref(),
            Some("2026-03-01 08:00")
        );
    }

    #[test]
    fn 记录图片格式化字符串按单个地址保留() {
        let body = serde_json::json!({
            "code": 1,
            "result": {"list": [{"record_id": 1, "images_fmt": "https://img/one"}]}
        })
        .to_string();
        let page = parse_records(&body, &[], 1, 10).expect("解析记录");
        assert_eq!(page.content[0].images, vec!["https://img/one"]);
    }

    #[test]
    fn 记录文本原语按冻结实现转为字符串() {
        let body = serde_json::json!({
            "code": 1,
            "result": {"list": [{"record_id": 1, "item_name": 7, "place": true}]}
        })
        .to_string();
        let page = parse_records(&body, &[], 1, 10).expect("解析记录");
        assert_eq!(page.content[0].item_name.as_deref(), Some("7"));
        assert_eq!(page.content[0].place.as_deref(), Some("true"));
    }

    #[test]
    fn 阳光打卡上传正文匹配冻结_multipart_字段() {
        let credential = YgdkCredential {
            uid: 7,
            token: "tok".into(),
        };
        let photo = YgdkPhotoUpload {
            file_name: "p.jpg".into(),
            mime_type: "image/jpeg".into(),
            bytes: b"PNG".to_vec(),
        };
        let body = String::from_utf8(build_upload_body(&credential, &photo, "b")).unwrap();
        assert!(body.contains("name=\"uid\"\r\n\r\n7"));
        assert!(body.contains("name=\"token\"\r\n\r\ntok"));
        assert!(body.contains("name=\"file\"; filename=\"p.jpg\""));
        assert!(body.ends_with("\r\n--b--\r\n"));
    }

    #[test]
    fn 无效打卡输入在任何网络请求前被拒绝() {
        let mut runtime = ClientRuntime::new(
            ConnectionMode::Direct,
            NoNetworkTransport,
            FileSessionStore::new(
                std::env::temp_dir().join(format!("ubaa-ygdk-input-{}", std::process::id())),
            )
            .unwrap(),
        )
        .unwrap();
        let result = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(super::submit_clockin(
                &mut runtime,
                YgdkClockinSubmitRequest::default(),
            ))
            .unwrap_err();
        assert_eq!(result.code, crate::error::ErrorCode::InvalidInput);
        assert_eq!(result.message, "打卡照片不能为空");
    }

    struct NoNetworkTransport;

    #[async_trait]
    impl HttpTransport for NoNetworkTransport {
        async fn execute(&self, _request: HttpRequest) -> crate::error::Result<HttpResponse> {
            panic!("无效输入不应触发网络请求");
        }
    }
}
