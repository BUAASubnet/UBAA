use super::{CLASS, YJ, changed, endpoint, isolated, observe, redirect};
use crate::{
    domain::{ConnectionMode, SecretValue},
    error::{Result, UbaaError},
    ports::HttpRequest,
    runtime::ClientRuntime,
};
use std::{
    sync::{Arc, LazyLock},
    time::UNIX_EPOCH,
};
use url::Url;
const LOGIN: &str = "https://yjapi.msa.buaa.edu.cn/casapi/index.php?r=auth/login&tenant_code=21&forward=https://classroom.msa.buaa.edu.cn/";
const FORWARD: &str = "https://classroom.msa.buaa.edu.cn/";
static TOKEN: LazyLock<regex::Regex> = LazyLock::new(|| {
    regex::Regex::new(r#"\{i:[0-9]+;s:6:"_token";i:[0-9]+;s:([0-9]+):"([A-Za-z0-9._-]+)";\}"#)
        .expect("课堂令牌格式")
});
fn missing() -> UbaaError {
    UbaaError::new(
        crate::error::ErrorCode::UpstreamUnavailable,
        crate::error::ErrorKind::Authentication,
        false,
        "未取得课堂认证凭据",
    )
    .with_diagnostic("msa_auth", "msa_token_missing")
}
fn token(raw: &str) -> Result<Arc<SecretValue>> {
    let mut bytes = raw.bytes();
    let mut decoded = Vec::with_capacity(raw.len());
    while let Some(byte) = bytes.next() {
        if byte == b'%' {
            let pair = [
                bytes.next().ok_or_else(missing)?,
                bytes.next().ok_or_else(missing)?,
            ];
            let mut result = [0];
            hex::decode_to_slice(pair, &mut result).map_err(|_| missing())?;
            decoded.push(result[0]);
        } else {
            decoded.push(byte);
        }
    }
    let value = String::from_utf8(decoded).map_err(|_| missing())?;
    let captures = TOKEN.captures(&value).ok_or_else(missing)?;
    let jwt = &captures[2];
    if jwt.len() > 4096 || captures[1].parse::<usize>().ok() != Some(jwt.len()) {
        return Err(missing());
    }
    Ok(Arc::new(SecretValue::new(jwt)))
}
fn cas(target: &Url, ticket: bool) -> bool {
    if !endpoint(target, YJ, "/casapi/index.php") {
        return false;
    }
    let pairs: Vec<_> = target.query_pairs().collect();
    pairs.len() == 3 + usize::from(ticket)
        && [
            ("r", "auth/login"),
            ("tenant_code", "21"),
            ("forward", FORWARD),
        ]
        .into_iter()
        .all(|(key, val)| {
            pairs
                .iter()
                .any(|(name, value)| name == key && value == val)
        })
        && (!ticket
            || pairs
                .iter()
                .any(|(key, value)| key == "ticket" && !value.is_empty()))
}
fn sso(target: &Url) -> bool {
    let mut pairs = target.query_pairs();
    endpoint(target, "sso.buaa.edu.cn", "/login")
        && pairs.next().is_some_and(|(key, val)| {
            key == "service" && Url::parse(&val).is_ok_and(|service| cas(&service, false))
        })
        && pairs.next().is_none()
}
async fn login(parent: &mut ClientRuntime) -> Result<Arc<SecretValue>> {
    let mode = parent.mode();
    let mut lane = isolated(parent);
    let result = chain(parent, &mut lane, mode).await;
    observe(parent, &mut lane);
    result
}
async fn chain(
    parent: &mut ClientRuntime,
    lane: &mut ClientRuntime,
    mode: ConnectionMode,
) -> Result<Arc<SecretValue>> {
    let mut current = Url::parse(LOGIN).expect("固定课堂登录地址");
    for hop in 0..4 {
        let url = parent.url(current.as_str())?;
        let runtime = if hop == 1 && mode == ConnectionMode::Direct {
            &mut *parent
        } else {
            &mut *lane
        };
        let response = runtime.request(HttpRequest::get(&url)).await?;
        if response.final_url != url {
            return Err(changed());
        }
        if response.status != 302 {
            return if matches!(response.status, 200 | 401) {
                Err(missing())
            } else {
                Err(crate::features::http::http_status_error(
                    &response,
                    "课堂认证",
                ))
            };
        }
        let next = redirect(&response, mode)?;
        if (hop == 0 || hop == 3) && endpoint(&next, CLASS, "/") && next.query().is_none() {
            if mode == ConnectionMode::Direct {
                let cookie = lane.cookie_value("_token", LOGIN)?.ok_or_else(missing)?;
                return token(&cookie);
            }
            let mut snap =
                Url::parse("https://d.buaa.edu.cn/wengine-vpn/cookie").expect("固定网关地址");
            let stamp = lane
                .now()
                .duration_since(UNIX_EPOCH)
                .map_err(|_| missing())?
                .as_millis()
                .to_string();
            snap.query_pairs_mut().extend_pairs([
                ("method", "get"),
                ("host", CLASS),
                ("scheme", "https"),
                ("path", "/coursedetail"),
                ("vpn_timestamp", stamp.as_str()),
            ]);
            let response = lane.request(HttpRequest::get(snap.as_str())).await?;
            if response.status != 200 || response.final_url != snap.as_str() {
                return Err(missing());
            }
            let body = std::str::from_utf8(&response.body).map_err(|_| missing())?;
            return token(
                body.split(';')
                    .filter_map(|field| field.trim().split_once('='))
                    .find(|(key, _)| *key == "_token")
                    .map(|(_, value)| value)
                    .ok_or_else(missing)?,
            );
        }
        if !match hop {
            0 => sso(&next),
            1 => cas(&next, true),
            2 => cas(&next, false),
            _ => false,
        } {
            return Err(changed());
        }
        current = next;
    }
    Err(changed())
}
pub(super) async fn credential(
    runtime: &mut ClientRuntime,
    rejected: Option<&Arc<SecretValue>>,
) -> Result<Arc<SecretValue>> {
    crate::features::require_session(runtime)?;
    let state = Arc::clone(&runtime.msa);
    let _guard = state.login_guard().await;
    runtime.ensure_session_revision()?;
    if runtime.authentication_revoked() {
        return Err(missing());
    }
    if let Some(cached) = state.credential() {
        if rejected.is_none_or(|old| !Arc::ptr_eq(old, &cached)) {
            return Ok(cached);
        }
        state.clear_credential();
    }
    let generation = state.generation();
    let fresh = login(runtime).await?;
    runtime.ensure_session_revision()?;
    if runtime.authentication_revoked() || !state.store_credential(generation, Arc::clone(&fresh)) {
        return Err(missing());
    }
    Ok(fresh)
}
pub(super) async fn reject(runtime: &ClientRuntime, old: &Arc<SecretValue>) -> Result<()> {
    runtime.ensure_session_revision()?;
    let _guard = runtime.msa.login_guard().await;
    if runtime
        .msa
        .credential()
        .is_some_and(|current| Arc::ptr_eq(old, &current))
    {
        runtime.msa.clear_credential();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    #[test]
    fn 令牌严格按前端百分号解码并且只接受数字索引() {
        let source = r#"a{i:0;s:6:"_token";i:1;s:3:"a-b";}"#;
        assert_eq!(super::token(source).unwrap().expose_secret(), "a-b");
        for value in [
            format!("%ZZ{source}"),
            format!("%FF{source}"),
            source.replace("i:0", "i:０"),
        ] {
            assert!(super::token(&value).is_err());
        }
    }

    #[test]
    fn 课堂令牌校验声明字节数和字符范围() {
        let encoded = |key_len, len, jwt: &str| {
            format!(r#"{{i:0;s:{key_len}:"_token";i:1;s:{len}:"{jwt}";}}"#)
        };
        for raw in [
            encoded(5, 3, "abc"),
            encoded(6, 2, "abc"),
            encoded(6, 3, "a+b"),
            encoded(6, 3, "中"),
            encoded(6, 4097, &"a".repeat(4097)),
        ] {
            assert!(super::token(&raw).is_err());
        }
        for jwt in ["A.b_9-z", &"a".repeat(4096)] {
            assert_eq!(
                super::token(&encoded(6, jwt.len(), jwt))
                    .unwrap()
                    .expose_secret(),
                jwt
            );
        }
    }
}
