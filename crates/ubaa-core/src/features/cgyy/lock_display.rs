//! 门锁专用白名单解析。
use crate::domain::CgyyLockDisplay;
use crate::error::Result;

pub(super) fn parse_lock_display(body: &str) -> Result<CgyyLockDisplay> {
    use super::parser::{data, error, string};
    let data = data(body)?;
    if data.is_null() {
        return Ok(CgyyLockDisplay::default());
    }
    let root = data
        .as_object()
        .ok_or_else(|| error("门锁信息结构不受支持"))?;
    if root
        .get("qrCode")
        .is_some_and(|v| !v.is_null() && !v.is_string())
        || (root.contains_key("password")
            && !root.contains_key("qrCode")
            && !root.contains_key("orderView"))
    {
        return Err(error("门锁信息结构不受支持"));
    }
    let clean = |value: Option<String>| {
        value
            .map(|s| s.trim().to_owned())
            .filter(|s| !s.is_empty() && s != "null")
    };
    let order = root.get("orderView").and_then(serde_json::Value::as_object);
    let field = |key| clean(order.and_then(|o| string(o, key)));
    Ok(CgyyLockDisplay {
        code: clean(
            root.get("qrCode")
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned),
        ),
        due_date: clean(string(root, "dueDate")),
        reservation_reference: field("tradeNo"),
        venue_name: field("venueName"),
        site_name: field("siteName"),
        space_name: field("venueSpaceName"),
        order_name: field("orderName"),
        reservation_date: field("reservationDate"),
        reservation_date_detail: field("reservationDateDetail"),
        reservation_start_date: field("reservationStartDate"),
        reservation_end_date: field("reservationEndDate"),
    })
}

pub(crate) async fn read(runtime: &mut crate::runtime::ClientRuntime) -> Result<CgyyLockDisplay> {
    let body = super::auth::get(
        runtime,
        "/api/orders/lock/code",
        std::collections::BTreeMap::new(),
    )
    .await?;
    parse_lock_display(&body)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn 保留门锁前导零和旧版预约摘要且不泄漏调试值() {
        let value = parse_lock_display(r#"{"code":200,"data":{"qrCode":" 001234 ","dueDate":"未知时区原文","orderView":{"tradeNo":"synthetic-reference","orderName":"合成人","venueName":"合成场地","siteName":"合成楼","venueSpaceName":"合成室","reservationDate":"2026-10-02","reservationDateDetail":"合成室 08:00-09:00","reservationStartDate":"开始原文","reservationEndDate":"结束原文"}}}"#).unwrap();
        assert_eq!(value.code.as_deref(), Some("001234"));
        assert_eq!(value.due_date.as_deref(), Some("未知时区原文"));
        assert_eq!(
            value.reservation_reference.as_deref(),
            Some("synthetic-reference")
        );
        assert_eq!(value.order_name.as_deref(), Some("合成人"));
        assert!(!format!("{value:?}").contains("001234"));
        assert!(!format!("{value:?}").contains("synthetic-reference"));
    }
    #[test]
    fn 门锁拒绝错误信封和未经证明的密码形状() {
        for body in [
            r#"{"code":500,"data":null}"#,
            r#"{"data":null}"#,
            r#"{"code":200,"data":{"password":"1234"}}"#,
            r#"{"code":200,"data":{"qrCode":1234}}"#,
            r#"{"code":200,"data":[]}"#,
        ] {
            assert!(parse_lock_display(body).is_err(), "必须拒绝不支持的形状");
        }
        assert!(
            parse_lock_display(r#"{"code":200,"data":null}"#)
                .unwrap()
                .code
                .is_none()
        );
        let value = parse_lock_display(r#"{"code":200,"data":{"qrCode":" null ","orderView":{"tradeNo":42,"reservationDate":"示例日期"}}}"#).unwrap();
        assert!(value.code.is_none());
        assert_eq!(value.reservation_reference.as_deref(), Some("42"));
    }
}
