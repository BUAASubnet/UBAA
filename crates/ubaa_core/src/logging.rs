//! 日志字段的安全投影。

/// 返回只保留协议和主机的 URL 日志摘要。
///
/// 路径、查询参数和片段可能包含订单号、会话标识或其他业务数据，统一不写入日志。
pub(crate) fn safe_url(value: &str) -> String {
    url::Url::parse(value).map_or_else(
        |_| "<无效 URL>".into(),
        |parsed| {
            let host = parsed.host_str().unwrap_or("<无主机>");
            format!("{}://{host}/<redacted>", parsed.scheme())
        },
    )
}

#[cfg(test)]
mod tests {
    use super::safe_url;

    #[test]
    fn url日志摘要不包含路径查询和片段() {
        let rendered = safe_url("https://example.test/orders/123?token=secret#fragment");
        assert_eq!(rendered, "https://example.test/<redacted>");
        assert!(!rendered.contains("orders"));
        assert!(!rendered.contains("secret"));
        assert!(!rendered.contains("fragment"));
    }
}
