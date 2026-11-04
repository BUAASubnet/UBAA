use super::{
    parse,
    wire::{self, EFAST, LINKS, ORIGIN},
};
use crate::domain::SecretValue;
use crate::error::{Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

pub(crate) fn id(input: &str) -> Result<String> {
    let id = if input.starts_with("https://") {
        let u = url::Url::parse(input).map_err(|_| UbaaError::invalid_input("分享链接无效"))?;
        if u.origin().ascii_serialization() != ORIGIN
            || u.query().is_some()
            || u.fragment().is_some()
        {
            return Err(UbaaError::invalid_input("请选择北航云盘分享链接"));
        }
        u.path()
            .strip_prefix("/link/")
            .ok_or_else(|| UbaaError::invalid_input("分享链接路径无效"))?
            .to_owned()
    } else {
        input.to_owned()
    };
    if id.is_empty()
        || !id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'-' | b'_'))
    {
        return Err(UbaaError::invalid_input("分享标识无效"));
    }
    Ok(id)
}

pub(crate) async fn open(
    runtime: &mut ClientRuntime,
    input: &str,
    password: Option<&SecretValue>,
) -> Result<(parse::Item, SecretValue)> {
    let id = id(input)?;
    // 分享授权使用独立临时 Cookie 容器，错误路径也随运行时释放。
    let mut temporary = runtime.fork_for_readonly_with_cookie_filter(|_| false);
    let info = get(&mut temporary, &format!("{ORIGIN}{LINKS}/links/{id}"), None).await?;
    let info: serde_json::Value = parse::json(&info)?;
    let required = info
        .get("password_required")
        .and_then(serde_json::Value::as_bool)
        .ok_or_else(parse::invalid)?;
    if required {
        let password = password.ok_or_else(|| UbaaError::invalid_input("该分享需要提取密码"))?;
        let body = serde_json::to_vec(&serde_json::json!({"id":id,"type":"anonymous","password_required":true,"password":password.expose_secret()})).map_err(|_| parse::invalid())?;
        let response = temporary
            .request_with_pre_send_check(
                HttpRequest::post(format!("{ORIGIN}/link"), body)
                    .with_header("Content-Type", "application/json"),
                ClientRuntime::ensure_session_revision,
            )
            .await?;
        if response.final_url != format!("{ORIGIN}/link") {
            return Err(parse::invalid());
        }
        wire::status(&response, false)?;
    } else {
        get(&mut temporary, &format!("{ORIGIN}/link/{id}"), None).await?;
    }
    let token = temporary
        .cookie_value(&format!("link_token:{id}"), &format!("{ORIGIN}/"))?
        .filter(|t| !t.is_empty())
        .ok_or_else(|| {
            UbaaError::new(
                crate::error::ErrorCode::PermissionDenied,
                crate::error::ErrorKind::Authentication,
                false,
                "分享授权不可用，请检查密码、有效期和权限",
            )
        })?;
    let token = SecretValue::new(token);
    let bytes = get(
        &mut temporary,
        &format!("{ORIGIN}{EFAST}/entry-item"),
        Some(&token),
    )
    .await?;
    runtime.ensure_session_revision()?;
    Ok((parse::received_share(&bytes)?, token))
}
async fn get(
    runtime: &mut ClientRuntime,
    url: &str,
    token: Option<&SecretValue>,
) -> Result<Vec<u8>> {
    let mut request = HttpRequest::get(url);
    if let Some(token) = token {
        request = request.with_header("Authorization", format!("Bearer {}", token.expose_secret()));
    }
    let response = runtime
        .request_with_pre_send_check(request, ClientRuntime::ensure_session_revision)
        .await?;
    if response.final_url != url {
        return Err(parse::invalid());
    }
    wire::status(&response, false)?;
    Ok(response.body)
}
