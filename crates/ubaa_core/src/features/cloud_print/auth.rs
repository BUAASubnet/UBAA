use base64::{Engine as _, engine::general_purpose::STANDARD};
use url::Url;

use crate::error::{ErrorCode, Result};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

use super::{
    HOST, PAGE, authentication_required, endpoint, envelope, https_origin, invalid, request,
};

const SSO_HOST: &str = "sso.buaa.edu.cn";
const LOGIN_PAGE: &str = "/authcenter/toLoginPage";
const APP_CALLBACK: &str = "/api/client/Auth/SSOLogin";
const UNIFIED_ENTRY: &str = "/api/client/Auth/UniEntry";

async fn check(runtime: &mut ClientRuntime) -> Result<()> {
    let response = request(
        runtime,
        // The print gateway rejects an empty POST without an explicit length (HTTP 411).
        HttpRequest::post(endpoint("Auth/Check").as_str(), Vec::new())
            .with_header("Content-Length", "0"),
    )
    .await?;
    let value = envelope(&response)?;
    let account = value["result"]["szLogonName"]
        .as_str()
        .filter(|v| !v.is_empty());
    if account.is_none()
        || runtime
            .account_name()
            .is_some_and(|expected| Some(expected) != account)
    {
        return Err(authentication_required());
    }
    Ok(())
}

pub(crate) async fn login(runtime: &mut ClientRuntime, sso: &mut ClientRuntime) -> Result<()> {
    let page = request(runtime, HttpRequest::get(PAGE)).await?;
    if page.status != 200 {
        return Err(invalid());
    }
    match check(runtime).await {
        Ok(()) => return Ok(()),
        Err(error) if error.code == ErrorCode::AuthenticationRequired => {}
        Err(error) => return Err(error),
    }
    let mut url = endpoint("Auth/SSoPage");
    url.query_pairs_mut().append_pair("backurl", PAGE);
    let response = request(runtime, HttpRequest::get(url.as_str())).await?;
    let envelope = envelope(&response)?;
    let mut current =
        Url::parse(envelope["result"].as_str().ok_or_else(invalid)?).map_err(|_| invalid())?;
    validate_bootstrap(&current)?;
    let mut service = None;
    for _ in 0..8 {
        let request_runtime = if current.host_str() == Some(SSO_HOST) {
            &mut *sso
        } else {
            &mut *runtime
        };
        let response = request(request_runtime, HttpRequest::get(current.as_str())).await?;
        if response.status == 200 {
            return if current.host_str() == Some(SSO_HOST) {
                Err(authentication_required())
            } else if current.path() == Url::parse(PAGE).expect("固定 URL").path() {
                check(runtime).await
            } else {
                Err(invalid())
            };
        }
        if !matches!(response.status, 301 | 302 | 303 | 307 | 308) {
            return Err(invalid());
        }
        let mut next = current
            .join(response.header_first("location").ok_or_else(invalid)?)
            .map_err(|_| invalid())?;
        if next.scheme() == "http"
            && next.host_str() == Some(HOST)
            && next.port().is_none()
            && next.path() == APP_CALLBACK
        {
            next.set_scheme("https").map_err(|()| invalid())?;
        }
        if https_origin(&next, SSO_HOST) && next.path() == "/login" && service.is_none() {
            let pairs: Vec<_> = next.query_pairs().collect();
            let [(name, value)] = pairs.as_slice() else {
                return Err(invalid());
            };
            if name != "service" {
                return Err(invalid());
            }
            let target = Url::parse(value).map_err(|_| invalid())?;
            if !https_origin(&target, HOST)
                || target.query().is_some()
                || !target
                    .path()
                    .strip_prefix("/authcenter/doAuth/")
                    .is_some_and(|id| id.len() == 32 && id.bytes().all(|v| v.is_ascii_hexdigit()))
            {
                return Err(invalid());
            }
            service = Some(target);
        } else if !https_origin(&next, HOST) {
            return Err(invalid());
        } else if current.path() == APP_CALLBACK && next.path() == UNIFIED_ENTRY {
            let mut session = false;
            let mut function = false;
            for (name, value) in next.query_pairs() {
                match name.as_ref() {
                    "SessionId" if !session && !value.is_empty() => session = true,
                    "Func" if !function && !value.is_empty() => function = true,
                    _ => return Err(invalid()),
                }
            }
            if service.is_none() || !session || !function {
                return Err(invalid());
            }
        } else if current.path() == UNIFIED_ENTRY {
            if next.as_str() != PAGE {
                return Err(invalid());
            }
        } else if !service.as_ref().is_some_and(|target| {
            target.path() == next.path()
                || matches!(
                    next.path(),
                    APP_CALLBACK | "/client/new/cprintPc/cprint.html"
                )
        }) {
            return Err(invalid());
        }
        current = next;
    }
    Err(invalid())
}

fn validate_bootstrap(url: &Url) -> Result<()> {
    if !https_origin(url, HOST) || url.path() != LOGIN_PAGE {
        return Err(invalid());
    }
    let mut pairs = url.query_pairs();
    let callback = pairs
        .find(|(key, _)| key == "redirectUrl")
        .ok_or_else(invalid)?
        .1;
    if callback != format!("http://{HOST}{APP_CALLBACK}")
        && callback != format!("https://{HOST}{APP_CALLBACK}")
    {
        return Err(invalid());
    }
    let target = url
        .query_pairs()
        .find(|(key, _)| key == "targetPageUrl")
        .ok_or_else(invalid)?
        .1;
    let decoded = STANDARD.decode(target.as_bytes()).map_err(|_| invalid())?;
    let target =
        Url::parse(std::str::from_utf8(&decoded).map_err(|_| invalid())?).map_err(|_| invalid())?;
    if !https_origin(&target, HOST)
        || target.path() != "/client/new/cprintPc/cprint.html"
        || url.query_pairs().count() != 2
        || target.query_pairs().count() != 1
        || !target
            .query_pairs()
            .all(|(key, value)| key == "sessionId" && !value.is_empty())
    {
        return Err(invalid());
    }
    Ok(())
}
