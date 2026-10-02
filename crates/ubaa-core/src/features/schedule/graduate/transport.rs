use super::{GraduateSchedule, error, parser};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::{HttpRequest, HttpResponse};
use crate::runtime::ClientRuntime;
const BASE: &str = "https://gsmis.buaa.edu.cn/gsapp/sys/wdkbapp";
const ENTRY: &str = "https://gsmis.buaa.edu.cn/gsapp/sys/wdkbapp/*default/index.do";

pub(super) async fn fetch(
    runtime: &mut ClientRuntime,
    term: Option<&str>,
) -> Result<GraduateSchedule> {
    crate::features::require_session(runtime)?;
    let response =
        crate::features::get_with_redirects(runtime, runtime.url(ENTRY)?, &[], "研究生课表")
            .await?;
    checked(&response)?;
    let response = post(runtime, "/modules/xskcb/kfdxnxqcx.do", None).await?;
    let terms = parser::parse_terms(&checked(&response)?)?;
    let selected = term
        .or_else(|| terms.first().map(|t| t.item_code.as_str()))
        .ok_or_else(error)?
        .to_owned();
    if !terms.iter().any(|t| t.item_code == selected) {
        return Err(error());
    }
    let form = url::form_urlencoded::Serializer::new(String::new())
        .extend_pairs([
            ("ZC", ""),
            ("XNXQDM", selected.as_str()),
            ("XH", ""),
            ("XQDM", ""),
        ])
        .finish();
    let response = post(runtime, "/bykb/loadXskbData.do", Some(form)).await?;
    parser::parse_schedule(&checked(&response)?, terms, &selected)
}
async fn post(
    runtime: &mut ClientRuntime,
    path: &str,
    form: Option<String>,
) -> Result<HttpResponse> {
    let mut request = HttpRequest::post(
        runtime.url(&format!("{BASE}{path}"))?,
        form.as_ref()
            .map_or_else(Vec::new, |s| s.as_bytes().to_vec()),
    );
    request.headers.insert(
        "Accept".into(),
        "application/json, text/javascript, */*; q=0.01".into(),
    );
    request
        .headers
        .insert("X-Requested-With".into(), "XMLHttpRequest".into());
    request
        .headers
        .insert("Referer".into(), runtime.url(ENTRY)?);
    if form.is_some() {
        request.headers.insert(
            "Content-Type".into(),
            "application/x-www-form-urlencoded".into(),
        );
    }
    runtime.request(request).await
}
fn checked(response: &HttpResponse) -> Result<String> {
    let body = crate::features::body(response);
    let is_login = |url: &str| {
        let direct = crate::connection::from_webvpn_url(url).unwrap_or_else(|_| url.to_owned());
        url::Url::parse(&direct)
            .is_ok_and(|u| u.host_str() == Some("sso.buaa.edu.cn") && u.path() == "/login")
    };
    if response.status == 401
        || is_login(&response.final_url)
        || body
            .to_ascii_lowercase()
            .contains("<title>cas login</title>")
        || body.contains("name=\"execution\"")
        || body.contains("name='execution'")
        || response
            .headers
            .iter()
            .filter(|(k, _)| k.eq_ignore_ascii_case("location"))
            .flat_map(|(_, v)| v)
            .any(|v| {
                url::Url::parse(&response.final_url)
                    .ok()
                    .and_then(|u| u.join(v).ok())
                    .is_some_and(|u| is_login(u.as_str()))
            })
    {
        return Err(UbaaError::new(
            ErrorCode::AuthenticationRequired,
            ErrorKind::Authentication,
            false,
            "研究生课表需要重新认证",
        ));
    }
    if response.status != 200 {
        return Err(UbaaError::new(
            if response.status >= 500 {
                ErrorCode::UpstreamUnavailable
            } else {
                ErrorCode::UpstreamChanged
            },
            ErrorKind::Upstream,
            false,
            "研究生课表请求未成功",
        ));
    }
    Ok(body)
}
