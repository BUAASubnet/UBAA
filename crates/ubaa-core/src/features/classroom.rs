//! 空闲教室响应解析器与已验证请求常量。
#![allow(clippy::missing_errors_doc)]

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::domain::{ClassroomInfo, ClassroomQuery};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// 空闲教室查询地址。
pub const CLASSROOM_URL: &str = "https://app.buaa.edu.cn/buaafreeclass/wap/default/search1";
/// 旧版实现中观察到的会话同步地址。
pub const CLASSROOM_SYNC_URL: &str = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fapp.buaa.edu.cn%2Fa_buaa%2Fapi%2Fcas%2Findex%3Fredirect%3Dhttps%253A%252F%252Fapp.buaa.edu.cn%252Fsite%252FclassRoomQuery%252Findex%26from%3Dwap%26login_from%3D&noAutoRedirect=1";
const CLASSROOM_USER_AGENT: &str = "Mozilla/5.0 (Linux; Android 16; 24031PN0DC Build/BP2A.250605.031.A3; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/138.0.7204.180 Mobile Safari/537.36 XWEB/1380275 MMWEBSDK/20230806 MMWEBID/4102 wxworklocal/3.2.200 wwlocal/3.2.200 wxwork/4.0.0 appname/wxworklocal-customized wxworklocal-device-code/195ef5586d7d3c2808fcbea32d77c0d4 MicroMessenger/7.0.1 appScheme/wxworklocalcustomized Language/zh_CN ColorScheme/Light WXWorklocalClientType/Android Brand/xiaomi";

#[derive(Debug, Deserialize)]
struct RawResponse {
    #[serde(rename = "e")]
    code: i32,
    #[serde(rename = "m")]
    message: String,
    #[serde(rename = "d")]
    data: RawData,
}

#[derive(Debug, Deserialize)]
struct RawData {
    list: BTreeMap<String, Vec<RawClassroom>>,
}

#[derive(Debug, Deserialize)]
struct RawClassroom {
    id: String,
    #[serde(rename = "floorid")]
    floor_id: String,
    name: String,
    #[serde(rename = "kxsds")]
    available_sections: String,
}

/// 解析教室 `e/m/d` 包装，同时允许合法的空列表。
pub fn parse_response(body: &str) -> Result<ClassroomQuery> {
    let response: RawResponse = serde_json::from_str(body).map_err(|_| {
        UbaaError::new(
            ErrorCode::ParseError,
            ErrorKind::Parse,
            false,
            "空教室响应不是有效 JSON",
        )
    })?;
    Ok(ClassroomQuery {
        code: response.code,
        message: response.message,
        floors: response
            .data
            .list
            .into_iter()
            .map(|(floor, rooms)| {
                (
                    floor,
                    rooms
                        .into_iter()
                        .map(|room| ClassroomInfo {
                            id: room.id,
                            floor_id: room.floor_id,
                            name: room.name,
                            available_sections: room.available_sections,
                        })
                        .collect(),
                )
            })
            .collect(),
    })
}

/// 查询指定校区和 ISO 日期的空闲教室。
pub(crate) async fn search(
    runtime: &mut crate::runtime::ClientRuntime,
    campus_id: i32,
    date: &str,
) -> Result<ClassroomQuery> {
    if !valid_iso_date(date) {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "日期必须使用 yyyy-mm-dd 格式",
        ));
    }
    let feature_state = runtime.feature_state();
    feature_state
        .classroom
        .ensure_synced(|| synchronize_session(runtime))
        .await;
    let query_url = runtime.url(CLASSROOM_URL)?;
    let referer = runtime.url("https://app.buaa.edu.cn/site/classRoomQuery/index")?;
    let mut url = url::Url::parse(&query_url).map_err(|_| {
        UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "空教室地址无效",
        )
    })?;
    url.query_pairs_mut()
        .append_pair("xqid", &campus_id.to_string())
        .append_pair("floorid", "")
        .append_pair("date", date);
    let response = super::get_with_headers(
        runtime,
        url.to_string(),
        &[
            ("User-Agent", CLASSROOM_USER_AGENT),
            ("Accept", "application/json, text/javascript, */*; q=0.01"),
            ("X-Requested-With", "XMLHttpRequest"),
            ("Referer", &referer),
        ],
    )
    .await?;
    let body = super::body(&response);
    if session_expired(&response, &body) {
        feature_state.classroom.clear();
        return Err(authentication_required());
    }
    check_query_status(response.status)?;
    parse_response(&body)
}

async fn synchronize_session(runtime: &mut crate::runtime::ClientRuntime) -> bool {
    let Ok(sync_url) = runtime.url(CLASSROOM_SYNC_URL) else {
        return false;
    };
    super::get_with_redirects(
        runtime,
        sync_url,
        &[("User-Agent", CLASSROOM_USER_AGENT)],
        "classroom",
    )
    .await
    .is_ok_and(|response| (200..400).contains(&response.status))
}

fn session_expired(response: &crate::ports::HttpResponse, body: &str) -> bool {
    if response.status == 401
        || is_sso_url(&response.final_url)
        || response_location_targets_sso(response)
    {
        return true;
    }
    let trimmed = body.trim_start();
    let is_html = starts_with_ignore_ascii_case(trimmed, "<!DOCTYPE html")
        || starts_with_ignore_ascii_case(trimmed, "<html");
    is_html
        && (body.contains("input name=\"execution\"")
            || body.contains("input name='execution'")
            || body.contains("统一身份认证"))
}

fn response_location_targets_sso(response: &crate::ports::HttpResponse) -> bool {
    response
        .headers
        .iter()
        .find(|(name, _)| name.eq_ignore_ascii_case("location"))
        .and_then(|(_, values)| values.first())
        .is_some_and(|location| {
            let resolved = url::Url::parse(&response.final_url)
                .ok()
                .and_then(|base| base.join(location).ok())
                .map_or_else(|| location.clone(), |target| target.to_string());
            is_sso_url(&resolved)
        })
}

fn is_sso_url(candidate: &str) -> bool {
    let direct = crate::connection::from_webvpn_url(candidate).unwrap_or_else(|_| candidate.into());
    url::Url::parse(&direct)
        .ok()
        .and_then(|url| url.host_str().map(str::to_ascii_lowercase))
        .is_some_and(|host| host == "sso.buaa.edu.cn")
}

fn starts_with_ignore_ascii_case(value: &str, prefix: &str) -> bool {
    value
        .get(..prefix.len())
        .is_some_and(|candidate| candidate.eq_ignore_ascii_case(prefix))
}

fn check_query_status(status: u16) -> Result<()> {
    if status >= 500 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            "空教室上游不可用",
        ));
    }
    if status != 200 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "空教室请求失败",
        ));
    }
    Ok(())
}

fn authentication_required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "空教室功能需要认证",
    )
}

fn valid_iso_date(date: &str) -> bool {
    let bytes = date.as_bytes();
    if bytes.len() != 10
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || !bytes[..4].iter().all(u8::is_ascii_digit)
        || !bytes[5..7].iter().all(u8::is_ascii_digit)
        || !bytes[8..].iter().all(u8::is_ascii_digit)
    {
        return false;
    }
    let year = u32::from(bytes[0] - b'0') * 1000
        + u32::from(bytes[1] - b'0') * 100
        + u32::from(bytes[2] - b'0') * 10
        + u32::from(bytes[3] - b'0');
    let month = u32::from(bytes[5] - b'0') * 10 + u32::from(bytes[6] - b'0');
    let day = u32::from(bytes[8] - b'0') * 10 + u32::from(bytes[9] - b'0');
    if !(1..=12).contains(&month) || day == 0 {
        return false;
    }
    let leap = year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400));
    let days_in_month = match month {
        2 if leap => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    };
    day <= days_in_month
}
