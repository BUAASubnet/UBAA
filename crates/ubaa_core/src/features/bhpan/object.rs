//! 只解析本次 API 响应中的对象授权，不接收宿主 URL。
use super::parse;
use crate::{
    error::{Result, UbaaError},
    ports::{HttpMethod, HttpRequest, HttpResponse},
};
use serde_json::Value;

pub(crate) fn authorization(value: &Value, method: HttpMethod) -> Result<HttpRequest> {
    let values = value.as_array().ok_or_else(parse::invalid)?;
    if values.len() < 2 {
        return Err(parse::invalid());
    }
    let expected = match method {
        HttpMethod::Get => "GET",
        HttpMethod::Put => "PUT",
        HttpMethod::Post => "POST",
        HttpMethod::Delete => return Err(parse::invalid()),
    };
    if values[0].as_str() != Some(expected) {
        return Err(parse::invalid());
    }
    let raw = values[1].as_str().ok_or_else(parse::invalid)?;
    let url = url::Url::parse(raw).map_err(|_| parse::invalid())?;
    if url.scheme() != "https"
        || url.host_str().is_none()
        || url.port_or_known_default().is_none_or(|port| port == 0)
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(parse::invalid());
    }
    let mut request = HttpRequest::get(raw);
    request.method = method;
    for header in values.iter().skip(2) {
        let (name, value) = header
            .as_str()
            .and_then(|value| value.split_once(':'))
            .ok_or_else(parse::invalid)?;
        let name = reqwest::header::HeaderName::from_bytes(name.trim().as_bytes())
            .map_err(|_| parse::invalid())?;
        let name = name.as_str();
        let value = value.trim();
        reqwest::header::HeaderValue::from_str(value).map_err(|_| parse::invalid())?;
        if matches!(
            name,
            "cookie"
                | "set-cookie"
                | "host"
                | "proxy-authorization"
                | "connection"
                | "transfer-encoding"
                | "range"
        ) || request.headers.insert(name.into(), value.into()).is_some()
        {
            return Err(parse::invalid());
        }
    }
    Ok(request)
}
pub(crate) fn download(bytes: &[u8], batch: bool) -> Result<HttpRequest> {
    let value: Value = parse::json(bytes)?;
    if batch {
        let raw = value
            .get("url")
            .and_then(Value::as_str)
            .ok_or_else(parse::invalid)?;
        authorization(&serde_json::json!(["GET", raw]), HttpMethod::Get)
    } else {
        authorization(
            value.get("authrequest").ok_or_else(parse::invalid)?,
            HttpMethod::Get,
        )
    }
}
pub(crate) fn success(request: &HttpRequest, response: &HttpResponse) -> Result<()> {
    if !(200..=299).contains(&response.status)
        || !crate::ports::same_url(&response.final_url, &request.url)
        || response.header_first("www-authenticate").is_some()
        || response.header_first("proxy-authenticate").is_some()
    {
        return Err(UbaaError::upstream_changed(
            "对象传输响应状态、认证或重定向不受支持",
        ));
    }
    Ok(())
}
pub(crate) fn completion(bytes: &[u8]) -> Result<(HttpRequest, Vec<u8>)> {
    let text = std::str::from_utf8(bytes).map_err(|_| parse::invalid())?;
    let (boundary, _) = text.split_once("\r\n").ok_or_else(parse::invalid)?;
    if !boundary.starts_with("--") || boundary.len() < 3 {
        return Err(parse::invalid());
    }
    let delimiter = format!("\r\n{boundary}");
    let mut xml = None;
    let mut auth = None;
    for part in text[boundary.len()..].split(&delimiter) {
        let part = part.trim_start_matches("\r\n");
        if part == "--\r\n" || part == "--" || part.is_empty() {
            continue;
        }
        let (_, body) = part.split_once("\r\n\r\n").ok_or_else(parse::invalid)?;
        if body.starts_with('<') && xml.is_none() {
            xml = Some(body.as_bytes().to_vec());
        } else if body.starts_with('{') && auth.is_none() {
            let value: Value = serde_json::from_str(body).map_err(|_| parse::invalid())?;
            auth = Some(authorization(
                value.get("authrequest").ok_or_else(parse::invalid)?,
                HttpMethod::Post,
            )?);
        } else {
            return Err(parse::invalid());
        }
    }
    Ok((
        auth.ok_or_else(parse::invalid)?,
        xml.ok_or_else(parse::invalid)?,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn 动态授权拒绝短数组错误方法不合法地址和越界头() {
        for value in [
            json!([]),
            json!(["PUT"]),
            json!(["POST", "https://object.invalid"]),
            json!(["PUT", "http://object.invalid"]),
            json!(["PUT", "https://user:password@object.invalid"]),
            json!(["PUT", "https://object.invalid#fragment"]),
            json!(["PUT", "https://object.invalid", "Cookie: value"]),
            json!(["PUT", "https://object.invalid", "Host: other.invalid"]),
            json!([
                "PUT",
                "https://object.invalid",
                "Authorization: value\r\nCookie: bad"
            ]),
        ] {
            assert!(authorization(&value, HttpMethod::Put).is_err());
        }
        let request = authorization(
            &json!([
                "PUT",
                "https://dynamic.invalid:8443/object?signature=synthetic",
                "Authorization: object-value",
                "Content-Type: application/octet-stream",
                "Date: synthetic"
            ]),
            HttpMethod::Put,
        )
        .unwrap();
        assert_eq!(request.headers["authorization"], "object-value");
        assert_eq!(request.headers.len(), 3);
        assert!(!format!("{request:?}").contains("object-value"));
        assert!(!format!("{request:?}").contains("signature"));
    }
    #[test]
    fn 非成功状态即使带_etag也不成功且重定向不跟随() {
        let request = HttpRequest::get("https://dynamic.invalid/object");
        for status in [302, 401, 403, 500] {
            let mut response = HttpResponse::new(status, request.url.clone(), vec![]);
            response
                .headers
                .insert("ETag".into(), vec!["quoted".into()]);
            assert!(success(&request, &response).is_err());
        }
    }
    #[test]
    fn 完成multipart保留_xml连字符且要求_xml与授权各一份() {
        let bytes=b"--fixture\r\nContent-Type: application/xml\r\n\r\n<Complete><ETag>part-with-hyphen</ETag></Complete>\r\n--fixture\r\nContent-Type: application/json\r\n\r\n{\"authrequest\":[\"POST\",\"https://object.invalid/complete\"]}\r\n--fixture--\r\n";
        let (request, xml) = completion(bytes).unwrap();
        assert_eq!(request.method, HttpMethod::Post);
        assert!(xml.windows(16).any(|value| value == b"part-with-hyphen"));
        assert!(completion(b"missing multipart").is_err());
    }
}

#[cfg(test)]
mod url_equivalence_test {
    use super::*;
    #[test]
    fn 默认端口规范化不会被误判成对象重定向() {
        let request = authorization(
            &serde_json::json!(["PUT", "https://object.invalid:443/data?signature=synthetic"]),
            HttpMethod::Put,
        )
        .unwrap();
        assert!(
            success(
                &request,
                &HttpResponse::new(
                    200,
                    "https://object.invalid/data?signature=synthetic",
                    vec![]
                )
            )
            .is_ok()
        );
        assert!(
            success(
                &request,
                &HttpResponse::new(
                    200,
                    "https://other.invalid/data?signature=synthetic",
                    vec![]
                )
            )
            .is_err()
        );
    }
}
