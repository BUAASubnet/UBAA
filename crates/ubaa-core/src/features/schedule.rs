//! 有证据支持的本科课表和考试解析器。
#![allow(
    clippy::missing_errors_doc,
    clippy::cast_possible_wrap,
    clippy::bool_to_int_with_if
)]

use serde::Deserialize;

use crate::domain::{Exam, ExamArrangement, Term, TodayClass, Week, WeeklySchedule};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// 冻结本地实现中观察到的学期地址。
pub const TERMS_URL: &str =
    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/schoolCalendars.do";
/// 教学周地址。
pub const WEEKS_URL: &str = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/getTermWeeks.do";
/// 周课表地址。
pub const WEEK_URL: &str =
    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do";
/// 今日课表地址。
pub const TODAY_URL: &str =
    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/teachingSchedule/detail.do";
/// 考试地址。
pub const EXAM_URL: &str = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/exams.do";
/// 冻结实现每次本科查询前使用的门户能力探测地址。
pub const CURRENT_USER_URL: &str =
    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/currentUser.do";
/// 固定 `buaa-api` 参考中的 AAS 专用 CAS 激活地址。
pub const AAS_LOGIN_URL: &str = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fbyxt.buaa.edu.cn%2Fjwapp%2Fsys%2Fhomeapp%2Findex.do%3FcontextPath%3D%2Fjwapp";
/// CAS 激活成功后预期的 AAS 落地页。
pub const AAS_VERIFY_URL: &str =
    "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp";
const SCHEDULE_REFERER_URL: &str = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.html";
const EXAM_REFERER_URL: &str = "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/home/index.html";

#[derive(Debug, Deserialize)]
struct ListResponse<T> {
    code: String,
    #[serde(default)]
    datas: Vec<T>,
}

#[derive(Debug, Deserialize)]
struct WeeklyResponse {
    #[serde(rename = "code")]
    _code: String,
    datas: WeeklySchedule,
}

#[derive(Debug, Deserialize)]
struct ExamResponse {
    code: String,
    #[serde(default)]
    datas: Vec<Exam>,
}

/// 解析已验证的学期包装。
pub fn parse_terms(body: &str) -> Result<Vec<Term>> {
    let response: ListResponse<Term> = parse_json(body)?;
    ensure_ok(&response.code, "schedule term response")?;
    Ok(response.datas)
}

/// 解析已验证的教学周包装。
pub fn parse_weeks(body: &str) -> Result<Vec<Week>> {
    let response: ListResponse<Week> = parse_json(body)?;
    Ok(response.datas)
}

/// 解析周课表包装。
pub fn parse_weekly_schedule(body: &str) -> Result<WeeklySchedule> {
    let response: WeeklyResponse = parse_json(body)?;
    Ok(response.datas)
}

/// 解析今日课表包装。
pub fn parse_today(body: &str) -> Result<Vec<TodayClass>> {
    let response: ListResponse<TodayClass> = parse_json(body)?;
    Ok(response.datas)
}

/// 解析考试安排包装。
pub fn parse_exam(body: &str) -> Result<ExamArrangement> {
    let response: ExamResponse = parse_json(body)?;
    ensure_ok(&response.code, "exam response")?;
    Ok(ExamArrangement {
        arranged: response.datas,
        not_arranged: Vec::new(),
    })
}

/// 通过当前认证路线获取学期。
pub(crate) async fn get_terms(runtime: &mut crate::runtime::ClientRuntime) -> Result<Vec<Term>> {
    ensure_undergraduate_portal(runtime).await?;
    let url = runtime.url(TERMS_URL)?;
    let referer = runtime.url(SCHEDULE_REFERER_URL)?;
    let response = super::get_with_redirects(
        runtime,
        url,
        &[
            ("Accept", "application/json, text/javascript, */*; q=0.01"),
            ("X-Requested-With", "XMLHttpRequest"),
            ("Referer", &referer),
        ],
        "schedule",
    )
    .await?;
    super::check_response(&response, "schedule")?;
    parse_terms(&super::body(&response))
}

/// 获取一个学期的教学周。
pub(crate) async fn get_weeks(
    runtime: &mut crate::runtime::ClientRuntime,
    term: &str,
) -> Result<Vec<Week>> {
    if term.trim().is_empty() {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "学期不能为空",
        ));
    }
    ensure_undergraduate_portal(runtime).await?;
    let mut url = url::Url::parse(&runtime.url(WEEKS_URL)?).map_err(|_| invalid_url())?;
    url.query_pairs_mut().append_pair("termCode", term);
    let referer = runtime.url(SCHEDULE_REFERER_URL)?;
    let response = super::get_with_redirects(
        runtime,
        url.to_string(),
        &[
            ("Accept", "application/json, text/javascript, */*; q=0.01"),
            ("X-Requested-With", "XMLHttpRequest"),
            ("Referer", &referer),
        ],
        "schedule",
    )
    .await?;
    super::check_response(&response, "schedule")?;
    parse_weeks(&super::body(&response))
}

/// 获取指定编号的教学周。
pub(crate) async fn get_week(
    runtime: &mut crate::runtime::ClientRuntime,
    term: &str,
    week: i32,
) -> Result<WeeklySchedule> {
    ensure_undergraduate_portal(runtime).await?;
    let url = runtime.url(WEEK_URL)?;
    let referer = runtime.url(SCHEDULE_REFERER_URL)?;
    let response = super::post_form(
        runtime,
        url,
        &[
            ("termCode", term.into()),
            ("type", "week".into()),
            ("week", week.to_string()),
        ],
        &[
            ("Accept", "application/json, text/javascript, */*; q=0.01"),
            ("X-Requested-With", "XMLHttpRequest"),
            ("Referer", &referer),
        ],
    )
    .await?;
    super::check_response(&response, "schedule")?;
    parse_weekly_schedule(&super::body(&response))
}

/// 使用上海日历日期获取今日课程。
pub(crate) async fn get_today(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<Vec<TodayClass>> {
    ensure_undergraduate_portal(runtime).await?;
    let mut url = url::Url::parse(&runtime.url(TODAY_URL)?).map_err(|_| invalid_url())?;
    url.query_pairs_mut()
        .append_pair("rq", &shanghai_date())
        .append_pair("lxdm", "student");
    let referer = runtime.url(SCHEDULE_REFERER_URL)?;
    let response = super::get_with_redirects(
        runtime,
        url.to_string(),
        &[
            ("Accept", "application/json, text/javascript, */*; q=0.01"),
            ("X-Requested-With", "XMLHttpRequest"),
            ("Referer", &referer),
        ],
        "schedule",
    )
    .await?;
    super::check_response(&response, "schedule")?;
    parse_today(&super::body(&response))
}

/// 获取一个学期的考试安排。
pub(crate) async fn get_exam(
    runtime: &mut crate::runtime::ClientRuntime,
    term: &str,
) -> Result<ExamArrangement> {
    ensure_undergraduate_portal(runtime).await?;
    let mut url = url::Url::parse(&runtime.url(EXAM_URL)?).map_err(|_| invalid_url())?;
    url.query_pairs_mut().append_pair("termCode", term);
    let referer = runtime.url(EXAM_REFERER_URL)?;
    let response = super::get_with_redirects(
        runtime,
        url.to_string(),
        &[
            ("Accept", "*/*"),
            ("X-Requested-With", "XMLHttpRequest"),
            ("Referer", &referer),
        ],
        "exam",
    )
    .await?;
    super::check_response(&response, "exam")?;
    parse_exam(&super::body(&response))
}

async fn ensure_undergraduate_portal(runtime: &mut crate::runtime::ClientRuntime) -> Result<()> {
    let mut response = probe_undergraduate_portal(runtime).await?;
    if undergraduate_portal_requires_sso(&response) {
        activate_undergraduate_portal(runtime).await?;
        response = probe_undergraduate_portal(runtime).await?;
    }
    classify_undergraduate_portal(&response)
}

async fn probe_undergraduate_portal(
    runtime: &mut crate::runtime::ClientRuntime,
) -> Result<crate::ports::HttpResponse> {
    let referer = runtime.url(SCHEDULE_REFERER_URL)?;
    super::get_with_redirects(
        runtime,
        runtime.url(CURRENT_USER_URL)?,
        &[
            ("Accept", "application/json, text/javascript, */*; q=0.01"),
            ("X-Requested-With", "XMLHttpRequest"),
            ("Referer", &referer),
        ],
        "schedule",
    )
    .await
}

async fn activate_undergraduate_portal(runtime: &mut crate::runtime::ClientRuntime) -> Result<()> {
    let response =
        super::get_with_redirects(runtime, runtime.url(AAS_LOGIN_URL)?, &[], "schedule").await?;
    super::check_response(&response, "schedule")?;
    let final_url = crate::connection::from_webvpn_url(&response.final_url)
        .unwrap_or_else(|_| response.final_url.clone());
    if !final_url.starts_with(AAS_VERIFY_URL) {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "本科教务门户激活后到达了非预期页面",
        ));
    }
    Ok(())
}

fn undergraduate_portal_requires_sso(response: &crate::ports::HttpResponse) -> bool {
    let text = super::body(response);
    response.status == 401
        || response.final_url.contains("sso.buaa.edu.cn")
        || text.contains("input name=\"execution\"")
        || text.contains("统一身份认证")
}

fn classify_undergraduate_portal(response: &crate::ports::HttpResponse) -> Result<()> {
    if undergraduate_portal_requires_sso(response) {
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "本科教务门户需要认证",
        ));
    }
    if response.final_url.contains("/jwapp/sys/byrhmhsy/") {
        return Err(UbaaError::new(
            ErrorCode::PermissionDenied,
            ErrorKind::Authentication,
            false,
            "本科教务门户不支持当前账户",
        ));
    }
    if response.status >= 500 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamUnavailable,
            ErrorKind::Upstream,
            true,
            "本科教务门户不可用",
        ));
    }
    if response.status != 200 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "本科教务门户探测失败",
        ));
    }
    Ok(())
}

fn invalid_url() -> crate::error::UbaaError {
    crate::error::UbaaError::new(
        crate::error::ErrorCode::UpstreamChanged,
        crate::error::ErrorKind::Upstream,
        false,
        "只读地址无效",
    )
}

fn shanghai_date() -> String {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |value| value.as_secs())
        + 8 * 60 * 60;
    let days = seconds / 86_400;
    let (year, month, day) = civil_date(days as i64);
    format!("{year:04}-{month:02}-{day:02}")
}

fn civil_date(days_since_epoch: i64) -> (i64, i64, i64) {
    let z = days_since_epoch + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    let year = year + if month <= 2 { 1 } else { 0 };
    (year, month, day)
}

fn parse_json<T: for<'de> Deserialize<'de>>(body: &str) -> Result<T> {
    serde_json::from_str(body).map_err(|_| {
        UbaaError::new(
            ErrorCode::ParseError,
            ErrorKind::Parse,
            false,
            "只读响应不是有效 JSON",
        )
    })
}

fn ensure_ok(code: &str, context: &str) -> Result<()> {
    if code == "0" {
        Ok(())
    } else {
        Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            format!("{context} returned a nonzero code"),
        ))
    }
}

#[cfg(test)]
#[path = "schedule/contract_tests.rs"]
mod contract_tests;
