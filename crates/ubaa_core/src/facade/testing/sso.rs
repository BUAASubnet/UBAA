//! 业务测试共用的合成 CAS 票据与身份资料，认证协议本身由独立测试覆盖。
use super::{HttpRequest, HttpResponse, from_webvpn_url};

/// 为已知 service 构造合成取票响应。
#[must_use]
pub fn sso_fixture_ticket(request: &HttpRequest) -> Option<HttpResponse> {
    let direct = from_webvpn_url(&request.url).ok()?;
    if direct
        == "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fd.buaa.edu.cn%2Flogin%3Fcas_login%3Dtrue"
    {
        let mut response = HttpResponse::new(302, &request.url, Vec::new());
        response
            .headers
            .insert("Location".into(), vec!["https://d.buaa.edu.cn/".into()]);
        return Some(response);
    }
    if request.url == "https://d.buaa.edu.cn/" {
        return Some(HttpResponse::new(
            200,
            &request.url,
            b"gateway ready".to_vec(),
        ));
    }
    if direct != crate::features::schedule::AAS_LOGIN_URL {
        return None;
    }
    let mut response = HttpResponse::new(302, &request.url, Vec::new());
    response.headers.insert("Location".into(), vec!["https://byxt.buaa.edu.cn/jwapp/sys/homeapp/index.do?contextPath=/jwapp&ticket=ST-fixture".into()]);
    Some(response)
}

/// 同一份合成用户资料可用于 UC 资料测试及 SSO 身份测试。
#[must_use]
pub fn sso_fixture_response(status: u16, url: impl Into<String>, body: Vec<u8>) -> HttpResponse {
    let url = url.into();
    let mut response = HttpResponse::new(status, &url, body);
    if from_webvpn_url(&url).is_ok_and(|direct| direct.contains("/serviceValidate"))
        && let Ok(payload) = serde_json::from_slice::<serde_json::Value>(&response.body)
    {
        if payload["code"] == 0 {
            let profile = &payload["data"];
            let school_id = profile
                .get("schoolid")
                .or_else(|| profile.get("schoolId"))
                .or_else(|| profile.get("username"))
                .cloned()
                .unwrap_or_default();
            response.body = serde_json::to_vec(&serde_json::json!({
                "user":profile["username"],
                "attributes":{"employeeNumber":[school_id],"name":[profile["name"]]}
            }))
            .unwrap();
        } else if payload.get("code").is_some() {
            response.body =
                br#"{"serviceResponse":{"authenticationFailure":{"code":"INVALID_TICKET"}}}"#
                    .to_vec();
        }
    }
    response
}
