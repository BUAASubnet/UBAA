//! SPOC 课堂目录、播放源和教学材料的只读访问。
mod auth;
mod parse;
#[cfg(test)]
mod tests;
use crate::{
    domain::{
        ConnectionMode,
        spoc_classroom::{
            ClassSummary, ClassroomCatalog, ClassroomSession, SlideTimeline, Transcript,
        },
    },
    error::{ErrorCode, Result, UbaaError},
    features::spoc,
    ports::{HttpRequest, HttpResponse},
    runtime::ClientRuntime,
};
use serde_json::Value;
use url::Url;
pub(super) const CLASS: &str = "classroom.msa.buaa.edu.cn";
const YJ: &str = "yjapi.msa.buaa.edu.cn";
const RESOURCE: &str = "resource.msa.buaa.edu.cn";
#[track_caller]
pub(super) fn changed(stage: &'static str, reason: &'static str) -> UbaaError {
    UbaaError::upstream_changed("课堂直录播上游协议变化").with_diagnostic(stage, reason)
}
pub(super) fn diagnose_changed(
    error: UbaaError,
    stage: &'static str,
    reason: &'static str,
) -> UbaaError {
    if error.code == ErrorCode::UpstreamChanged {
        error.with_diagnostic(stage, reason)
    } else {
        error
    }
}
pub(super) fn digits(id: &str) -> bool {
    (1..=20).contains(&id.len()) && id.bytes().all(|byte| byte.is_ascii_digit())
}
fn guid(id: &str) -> bool {
    (1..=64).contains(&id.len()) && id.bytes().all(|byte| byte.is_ascii_alphanumeric())
}
fn check(ids: &[&str], resource: Option<&str>) -> Result<()> {
    if ids.iter().all(|id| digits(id)) && resource.is_none_or(guid) {
        Ok(())
    } else {
        Err(UbaaError::invalid_input("课堂标识无效"))
    }
}
pub(super) fn origin(url: &Url, host: &str) -> bool {
    url.scheme() == "https"
        && url.host_str() == Some(host)
        && url.port().is_none()
        && url.username().is_empty()
        && url.password().is_none()
}
pub(super) fn endpoint(url: &Url, host: &str, path: &str) -> bool {
    origin(url, host) && url.path() == path && url.fragment().is_none()
}
pub(super) fn redirect(
    response: &HttpResponse,
    mode: ConnectionMode,
    stage: &'static str,
) -> Result<Url> {
    let location = response
        .header_first("location")
        .ok_or_else(|| changed(stage, "redirect_location_missing"))?;
    let raw = Url::parse(&response.final_url)
        .and_then(|base| base.join(location))
        .map_err(|_| changed(stage, "redirect_location_invalid"))?;
    if raw.scheme() != "https"
        || (raw.host_str() == Some("d.buaa.edu.cn")
            && (mode != ConnectionMode::WebVpn
                || !crate::connection::is_valid_webvpn_gateway(&raw)))
    {
        return Err(changed(stage, "redirect_location_untrusted"));
    }
    let url = crate::connection::business_redirect_target(&response.final_url, location)
        .map_err(|_| changed(stage, "redirect_location_unwrap"))?;
    if url.scheme() != "https" {
        return Err(changed(stage, "redirect_target_scheme"));
    }
    Ok(url)
}
fn media_url(raw: &str, host: &str, mode: ConnectionMode) -> Option<String> {
    let url = parse_media_url(raw)?;
    let direct = if mode == ConnectionMode::WebVpn && origin(&url, "d.buaa.edu.cn") {
        parse_media_url(&crate::connection::from_webvpn_url(url.as_str()).ok()?)?
    } else {
        url
    };
    origin(&direct, host).then(|| direct.into())
}
fn parse_media_url(raw: &str) -> Option<Url> {
    if raw
        .chars()
        .any(|ch| ch == '\\' || ch.is_whitespace() || ch.is_ascii_control())
    {
        return None;
    }
    let authority = raw.split_once("://")?.1.split(['/', '?', '#']).next()?;
    if authority.is_empty() || authority.contains('@') {
        return None;
    }
    Url::parse(raw).ok()
}
fn isolated(runtime: &ClientRuntime) -> ClientRuntime {
    let vpn = runtime.mode() == ConnectionMode::WebVpn;
    runtime.fork_with_cookie_filter(|cookie| {
        vpn && cookie.name != "_token"
            && matches!(
                cookie.domain.trim_start_matches('.'),
                "d.buaa.edu.cn" | "buaa.edu.cn"
            )
    })
}
fn observe(parent: &mut ClientRuntime, lane: &mut ClientRuntime) {
    parent.reached_domains.append(&mut lane.reached_domains);
    if let Some(domain) = lane.network_failure_domain.take() {
        parent.network_failure_domain = Some(domain);
    }
}
pub(super) async fn isolated_get(
    runtime: &mut ClientRuntime,
    request: HttpRequest,
) -> Result<HttpResponse> {
    let mut lane = isolated(runtime);
    let response = lane.request(request).await;
    observe(runtime, &mut lane);
    response
}
enum Api {
    Catalog,
    Session,
    Transcript,
    Summary,
    Slides,
}
impl Api {
    fn stage(&self) -> &'static str {
        match self {
            Self::Catalog => "msa_catalog",
            Self::Session => "msa_session",
            Self::Transcript => "msa_transcript",
            Self::Summary => "msa_summary",
            Self::Slides => "msa_slides",
        }
    }

    fn endpoint(&self) -> &'static str {
        match self {
            Self::Catalog => {
                "https://yjapi.msa.buaa.edu.cn/courseapi/v3/multi-search/get-course-detail"
            }
            Self::Session => {
                "https://classroom.msa.buaa.edu.cn/courseapi/v3/portal-home-setting/get-sub-info"
            }
            Self::Transcript => {
                "https://yjapi.msa.buaa.edu.cn/courseapi/v3/web-socket/search-trans-result"
            }
            Self::Summary => {
                "https://classroom.msa.buaa.edu.cn/courseapi/v2/intelligent-summary/detail"
            }
            Self::Slides => "https://classroom.msa.buaa.edu.cn/pptnote/v1/schedule/search-ppt",
        }
    }
    async fn get(&self, runtime: &mut ClientRuntime, pairs: &[(&str, &str)]) -> Result<Value> {
        let stage = self.stage();
        let mut target = Url::parse(self.endpoint()).expect("固定课堂接口");
        target.query_pairs_mut().extend_pairs(pairs.iter().copied());
        let routed = runtime.url(target.as_str())?;
        let mut jwt = auth::credential(runtime, None).await?;
        for attempt in 0..2 {
            let request = HttpRequest::get(&routed)
                .with_header("Authorization", format!("Bearer {}", jwt.expose_secret()));
            let response = isolated_get(runtime, request).await?;
            if response.final_url != routed {
                return Err(changed(stage, "api_final_target"));
            }
            if response.status != 401 {
                if response.status != 200 {
                    let error = super::http::http_status_error(&response, "课堂直录播");
                    return Err(diagnose_changed(error, stage, "api_http_status"));
                }
                let payload: Value = serde_json::from_slice(&response.body)
                    .map_err(|_| changed(stage, "api_json_invalid"))?;
                let code = payload["code"]
                    .as_i64()
                    .or_else(|| {
                        matches!(self, Self::Summary)
                            .then(|| payload["result"]["code"].as_i64())
                            .flatten()
                    })
                    .ok_or_else(|| changed(stage, "api_code_shape"))?;
                if code != 5002 {
                    let success = if matches!(self, Self::Summary) {
                        payload["success"] == true && code == 200
                    } else {
                        code == 0
                    };
                    if success {
                        return Ok(payload);
                    }
                    return Err(UbaaError::upstream_unavailable("课堂业务读取失败")
                        .with_upstream_code(code));
                }
            }
            if attempt == 0 {
                jwt = auth::credential(runtime, Some(&jwt)).await?;
            } else {
                auth::reject(runtime, &jwt).await?;
                return spoc::arbitrate_classroom_auth(runtime).await;
            }
        }
        unreachable!("第二次认证失败已交由主会话核验")
    }
}
pub(crate) async fn catalog(runtime: &mut ClientRuntime, kcid: &str) -> Result<ClassroomCatalog> {
    let (course, username) = spoc::classroom::map(runtime, kcid).await?;
    let result = Api::Catalog
        .get(runtime, &[("course_id", &course), ("student", &username)])
        .await?;
    parse::catalog(&result["data"], &course)
}
pub(crate) async fn session(
    runtime: &mut ClientRuntime,
    course: &str,
    sub: &str,
) -> Result<ClassroomSession> {
    check(&[course, sub], None)?;
    let result = Api::Session
        .get(runtime, &[("course_id", course), ("sub_id", sub)])
        .await?;
    parse::session(&result["data"], runtime.mode())
}
pub(crate) async fn transcript(
    runtime: &mut ClientRuntime,
    sub: &str,
    resource: &str,
) -> Result<Transcript> {
    check(&[sub], Some(resource))?;
    let result = Api::Transcript
        .get(
            runtime,
            &[
                ("sub_id", sub),
                ("format", "json"),
                ("resource_guid", resource),
            ],
        )
        .await?;
    parse::transcript(&result)
}
pub(crate) async fn summary(
    runtime: &mut ClientRuntime,
    sub: &str,
    resource: &str,
) -> Result<ClassSummary> {
    check(&[sub], Some(resource))?;
    let result = Api::Summary
        .get(runtime, &[("sub_id", sub), ("resource_guid", resource)])
        .await?;
    parse::summary(&result)
}
pub(crate) async fn slides(
    runtime: &mut ClientRuntime,
    course: &str,
    sub: &str,
    resource: &str,
) -> Result<SlideTimeline> {
    check(&[course, sub], Some(resource))?;
    let result = Api::Slides
        .get(
            runtime,
            &[
                ("course_id", course),
                ("sub_id", sub),
                ("page", "1"),
                ("per_page", "100"),
                ("resource_guid", resource),
            ],
        )
        .await?;
    parse::slides(&result, runtime.mode())
}
