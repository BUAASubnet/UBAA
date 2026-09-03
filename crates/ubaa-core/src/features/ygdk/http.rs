//! 阳光打卡表单请求、query 双写与公共请求头。

use crate::error::Result;
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

use super::YgdkCredential;
use super::parser::error;

pub(super) const FRONT_BASE: &str = "https://ygdk.buaa.edu.cn";

pub(super) async fn post(
    runtime: &mut ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    params: &[(&str, String)],
) -> Result<String> {
    post_request(runtime, path, credential, params, false).await
}

pub(super) async fn post_with_query(
    runtime: &mut ClientRuntime,
    path: &str,
    credential: &YgdkCredential,
    params: &[(&str, String)],
) -> Result<String> {
    post_request(runtime, path, credential, params, true).await
}

async fn post_request(
    runtime: &mut ClientRuntime,
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
    Ok(super::super::body(&response))
}
