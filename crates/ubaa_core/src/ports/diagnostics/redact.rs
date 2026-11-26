use super::{HttpResponse, Value};
use std::collections::BTreeMap;
use url::Url;

const HIDDEN: &str = "[已隐藏]";
fn private(key: &str) -> bool {
    matches!(
        key.to_ascii_lowercase().as_str(),
        "authorization"
            | "_token"
            | "ticket"
            | "signature"
            | "username"
            | "realname"
            | "lecturer_name"
            | "bind_id"
            | "timestamp"
            | "auth_key"
    )
}
fn private_query(key: &str) -> bool {
    private(key)
        || matches!(
            key.to_ascii_lowercase().as_str(),
            "sign" | "time" | "once" | "student" | "token"
        )
}
pub(super) fn url(raw: &str) -> String {
    let (base, fragment) = raw
        .split_once('#')
        .map_or((raw, None), |(base, fragment)| (base, Some(fragment)));
    let mut output = base.split_once('?').map_or_else(
        || base.into(),
        |(path, query)| format!("{path}?{}", redact_pairs(query)),
    );
    if let Some(fragment) = fragment {
        output.push('#');
        if let Some((path, query)) = fragment
            .split_once('?')
            .filter(|(path, _)| !path.contains('='))
        {
            output.push_str(path);
            output.push('?');
            output.push_str(&redact_pairs(query));
        } else {
            output.push_str(&redact_pairs(fragment));
        }
    }
    output
}
fn redact_pairs(query: &str) -> String {
    let pairs = url::form_urlencoded::parse(query.as_bytes());
    if !pairs
        .clone()
        .any(|(key, value)| private_query(&key) || value.contains('?'))
    {
        return query.into();
    }
    let mut result = url::form_urlencoded::Serializer::new(String::new());
    for (key, value) in pairs {
        if private_query(&key) || value.contains('?') {
            result.append_pair(&key, HIDDEN);
        } else {
            result.append_pair(&key, &value);
        }
    }
    result.finish()
}
fn cookie(raw: &str, mask_all: bool, set_cookie: bool) -> String {
    raw.split(';')
        .enumerate()
        .map(|(index, field)| {
            if let Some((name, _)) = field.split_once('=')
                && (!set_cookie || index == 0)
                && (mask_all || name.trim() == "_token")
            {
                format!("{name}={HIDDEN}")
            } else {
                field.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join(";")
}
fn masks_all_cookies(raw: &str) -> bool {
    let Ok(url) = Url::parse(raw) else {
        return false;
    };
    if url.path().ends_with("/casapi/index.php") {
        return true;
    }
    match url.host_str() {
        Some("yjapi.msa.buaa.edu.cn" | "classroom.msa.buaa.edu.cn") => true,
        Some("d.buaa.edu.cn") => {
            url.path() == "/wengine-vpn/cookie"
                || crate::connection::from_webvpn_url(raw)
                    .ok()
                    .and_then(|direct| Url::parse(&direct).ok())
                    .is_some_and(|direct| {
                        matches!(
                            direct.host_str(),
                            Some("yjapi.msa.buaa.edu.cn" | "classroom.msa.buaa.edu.cn")
                        )
                    })
        }
        _ => false,
    }
}
pub(super) fn headers(request_url: &str, response: &HttpResponse) -> BTreeMap<String, Vec<String>> {
    let mask_all = masks_all_cookies(request_url)
        || (response.final_url != request_url && masks_all_cookies(&response.final_url));
    response
        .headers
        .iter()
        .map(|(key, values)| {
            let name = key.to_ascii_lowercase();
            (
                key.clone(),
                values
                    .iter()
                    .map(|value| match name.as_str() {
                        "authorization" => HIDDEN.into(),
                        "location" | "content-location" => url(value),
                        "cookie" | "set-cookie" => cookie(value, mask_all, name == "set-cookie"),
                        _ => value.clone(),
                    })
                    .collect(),
            )
        })
        .collect()
}
fn fields(value: &mut Value) -> bool {
    match value {
        Value::Object(map) => {
            let mut changed = false;
            for (key, item) in map {
                if private(key) {
                    *item = Value::String(HIDDEN.into());
                    changed = true;
                } else {
                    changed |= fields(item);
                }
            }
            changed
        }
        Value::Array(items) => {
            let mut changed = false;
            for item in items {
                changed |= fields(item);
            }
            changed
        }
        Value::String(text) => {
            let trimmed = text.trim_start();
            if trimmed.starts_with(['[', '{'])
                && let Ok(mut nested) = serde_json::from_str::<Value>(trimmed)
                && fields(&mut nested)
            {
                *text = nested.to_string();
                return true;
            }
            if ["http://", "https://"].iter().any(|prefix| {
                trimmed
                    .get(..prefix.len())
                    .is_some_and(|start| start.eq_ignore_ascii_case(prefix))
            }) {
                let safe = url(text);
                if *text != safe {
                    *text = safe;
                    return true;
                }
            }
            false
        }
        _ => false,
    }
}
pub(super) fn body(request_url: &str, bytes: &[u8]) -> Option<String> {
    let path = Url::parse(request_url).ok()?;
    if path.path() == "/wengine-vpn/cookie"
        || path.path().ends_with("/casapi/index.php")
        || path.path().ends_with("/getHxyTimestampAndSignature2")
        || path.path().ends_with("/get-bh-course-url")
    {
        return Some(HIDDEN.into());
    }
    let Ok(mut data) = serde_json::from_slice::<Value>(bytes) else {
        return [
            "/get-course-detail",
            "/get-sub-info",
            "/search-trans-result",
            "/intelligent-summary/detail",
            "/search-ppt",
        ]
        .iter()
        .any(|suffix| path.path().ends_with(suffix))
        .then(|| HIDDEN.into());
    };
    fields(&mut data).then(|| data.to_string())
}
