use super::parser;
use serde_json::{Value, json};

const PROFILE: &str = include_str!("../../../../../fixtures/readonly/campus/profile.json");
const NETWORK: &str = include_str!("../../../../../fixtures/readonly/campus/network.html");

#[test]
fn 主会话失效不降级为单项失败() {
    let error = crate::error::UbaaError::authentication_required("读取所属会话已失效");
    assert!(super::record::<u64>(Err(error), 1).is_err());
}

#[test]
fn 门户资料仅投影身份学院和时间() {
    let profile = parser::profile(&serde_json::from_str(PROFILE).unwrap(), 123).unwrap();
    assert_eq!(profile.identity, "本科生");
    assert_eq!(profile.department, "示例学院");
    let wire = serde_json::to_value(profile).unwrap();
    assert_eq!(
        wire,
        json!({"identity":"本科生","department":"示例学院","fetchedAt":123})
    );
}

#[test]
fn 金额接受混合数字并保留十进制精度() {
    for (input, expected) in [
        (r#"{"value":12.34,"unit":"元"}"#, "12.34"),
        (r#"{"value":"0.00","unit":"元"}"#, "0.00"),
        (
            r#"{"value":12345678901234567890.123456789,"unit":"元"}"#,
            "12345678901234567890.123456789",
        ),
    ] {
        let data: Value = serde_json::from_str(input).unwrap();
        let amount = parser::amount(&data).unwrap();
        assert_eq!(amount.value, expected);
        assert_eq!(amount.unit, "元");
    }
}

#[test]
fn 计数接受整数及字符串零值并拒绝不明数据() {
    assert_eq!(parser::count(&json!({"value":"0"})).unwrap(), 0);
    assert_eq!(parser::count(&json!({"value":7})).unwrap(), 7);
    for value in [
        json!(null),
        json!(true),
        json!(-1),
        json!(""),
        json!("1.5"),
        json!(1.5),
    ] {
        assert!(parser::count(&json!({"value":value})).is_err());
    }
    for value in [json!(null), json!(true), json!(-1), json!("")] {
        assert!(parser::amount(&json!({"value":value,"unit":"元"})).is_err());
    }
}

#[test]
fn 业务登录只接受当前回调和嵌套服务地址() {
    use super::{Service, login_target};
    use crate::domain::ConnectionMode;
    let mode = ConnectionMode::Direct;
    for target in [
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fexample.invalid%2Fsteal",
        "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fzfw.buaa.edu.cn%2Fsso%2Fcas%2Findex&ticket=fixture",
        "https://zfw.buaa.edu.cn/pay/card?ticket=fixture",
        "http://zfw.buaa.edu.cn/sso/cas/index",
        "https://user@zfw.buaa.edu.cn/sso/cas/index",
        "https://zfw.buaa.edu.cn/sso/cas/index?ticket=one&ticket=two",
    ] {
        assert!(login_target(Service::Network, target, mode).is_err());
    }
    assert!(
        login_target(
            Service::Portal,
            "https://zfw.buaa.edu.cn/sso/cas/index?ticket=fixture",
            mode
        )
        .is_err()
    );
    assert!(login_target(Service::Network, "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fzfw.buaa.edu.cn%2Fsso%2Fcas%2Findex", mode).is_ok());
    let wrapped = crate::connection::to_webvpn_url(super::NETWORK_LOGIN).unwrap();
    assert!(login_target(Service::Network, &wrapped, mode).is_err());
    assert!(login_target(Service::Network, &wrapped, ConnectionMode::WebVpn).is_ok());
}

#[path = "request_tests.rs"]
mod requests;

#[test]
fn 流量按表头匹配重排列并保留多个产品和单位() {
    let usage = parser::traffic(NETWORK, 456).unwrap();
    assert_eq!(usage.products.len(), 2);
    assert_eq!(usage.products[0].used.value, "90.001");
    assert_eq!(usage.products[0].billable_remaining.value, "40.125");
    assert_eq!(usage.products[0].free_remaining.unit, "byte");
    assert_eq!(usage.products[1].billable_remaining.unit, "M");
    assert!(usage.remaining_excludes_packages);
    assert_eq!(usage.fetched_at, 456);
}

#[test]
fn 流量缺表头重复列和登录页不能被解析成零() {
    for page in [
        NETWORK.replace("已用流量", "未知表头"),
        NETWORK.replace("data-col-seq=\"6\"", "data-col-seq=\"7\""),
        NETWORK.replace("40.125G", "未知"),
        "<form><input name=\"execution\"><input type=\"password\"></form>".into(),
    ] {
        assert!(parser::traffic(&page, 1).is_err());
    }
}
