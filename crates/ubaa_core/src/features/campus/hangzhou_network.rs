//! 杭州校区网费余额：深澜（Srun）上网认证网关的在线信息查询。
//!
//! 杭州上网自助服务平台不接统一认证（需杭州密码和图片验证码），但认证网关
//! `http://10.60.0.100/cgi-bin/rad_user_info` 对「当前已在线的设备」直接返回其上网账号与
//! `user_balance`，无需任何凭据；官方认证成功页即以 `user_balance.toFixed(2)` 显示「账户余额」
//! （2026-11-26 账号本人设备核对，只记录键形状）。因此：
//!
//! - 只在设备连着杭州校园网且已认证上网时可读，其他网络下本项失败，不影响其它指标；
//! - 网关返回的 `user_name` 必须等于本人学工号，避免把同一网络下他人账号的余额显示给用户；
//! - 请求最多等待 [`TIMEOUT`]，且不把私网网关的失败记为北京业务域的网络故障。

use std::time::Duration;

use serde_json::Value;
use tracing::debug;

use crate::domain::{CampusAmount, NetworkProductUsage, NetworkUsage};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

const USER_INFO: &str = "http://10.60.0.100/cgi-bin/rad_user_info?callback=ubaa";
const TIMEOUT: Duration = Duration::from_secs(4);

/// 网关在线信息中 UBAA 使用的部分；MAC、IP 等其余字段不读取。
#[derive(Debug)]
struct OnlineInfo {
    balance: f64,
    used_bytes: u64,
    product_name: String,
}

pub(crate) async fn balance(
    runtime: &mut ClientRuntime,
    school_id: Option<&str>,
) -> Result<CampusAmount> {
    let info = online_info(runtime, school_id).await?;
    Ok(CampusAmount {
        value: format!("{:.2}", info.balance),
        unit: "元".into(),
    })
}

/// 杭州校园网每月前 70 GB 免费（用户提供的计费规则；与认证页 1000 进制一致）。
const FREE_BYTES: u64 = 70_000_000_000;

/// 杭州「校园网流量」：已用流量与认证页 `sum_bytes` 换算一致；免费剩余按
/// 70 GB 减已用计算，超出后为 0；计费剩余 = 余额 × 4 GB（超出部分 0.25 元/GB）。
/// 网关的 `remain_bytes` 在电脑上等于余额 × 4 × 2^30，但同一账号在手机上返回 0，不可靠，不使用。
pub(crate) async fn usage(
    runtime: &mut ClientRuntime,
    school_id: Option<&str>,
    fetched_at: i64,
) -> Result<NetworkUsage> {
    let info = online_info(runtime, school_id).await?;
    let billable = billable_remaining(&info);
    Ok(NetworkUsage {
        products: vec![NetworkProductUsage {
            product_name: info.product_name,
            used: format_flow(info.used_bytes),
            free_remaining: Some(free_remaining(info.used_bytes)),
            billable_remaining: Some(billable),
        }],
        // 杭州没有套餐，不显示「免费剩余含套餐可用流量」。
        remaining_excludes_packages: true,
        fetched_at,
    })
}

/// 免费剩余统一以 GB 表示（保留两位），用量超过 70 GB 时为 0。
fn free_remaining(used_bytes: u64) -> CampusAmount {
    let remaining = FREE_BYTES.saturating_sub(used_bytes);
    #[allow(clippy::cast_precision_loss)]
    let gigabytes = remaining as f64 / 1e9;
    CampusAmount {
        value: format!("{gigabytes:.2}"),
        unit: "GB".into(),
    }
}

/// 计费剩余以 GB 表示（保留两位），余额为负时为 0。
fn billable_remaining(info: &OnlineInfo) -> CampusAmount {
    let gigabytes = (info.balance * 4.0).max(0.0);
    CampusAmount {
        value: format!("{gigabytes:.2}"),
        unit: "GB".into(),
    }
}

/// 与认证页 `formatFlow(sum_bytes, TrafficCarry=1000)` 一致：逐级除以 1000，保留两位小数。
fn format_flow(bytes: u64) -> CampusAmount {
    if bytes == 0 {
        return CampusAmount {
            value: "0".into(),
            unit: "B".into(),
        };
    }
    let units = ["B", "KB", "MB", "GB", "TB"];
    #[allow(clippy::cast_precision_loss)]
    let mut value = bytes as f64;
    let mut index = 0;
    while value >= 1000.0 && index + 1 < units.len() {
        value /= 1000.0;
        index += 1;
    }
    CampusAmount {
        value: format!("{value:.2}"),
        unit: units[index].into(),
    }
}

async fn online_info(runtime: &mut ClientRuntime, school_id: Option<&str>) -> Result<OnlineInfo> {
    let school_id = school_id
        .map(str::trim)
        .filter(|id| !id.is_empty())
        .ok_or_else(|| unavailable("无法确认本人学工号，暂不能读取杭州网费"))?;
    let previous_failure = runtime.network_failure_domain.clone();
    let mut request = HttpRequest::get(USER_INFO.to_owned());
    request.headers.insert("Accept".into(), "*/*".into());
    let result = tokio::time::timeout(TIMEOUT, runtime.request(request)).await;
    // 私网认证网关不可达只说明不在杭州校园网，不能影响北京业务的线路判断。
    runtime.network_failure_domain = previous_failure;
    let Ok(Ok(response)) = result else {
        return Err(not_on_campus());
    };
    debug!(target: "ubaa::hz_network", status = response.status, body_len = response.body.len(), "收到杭州认证网关响应");
    if response.status != 200 {
        return Err(not_on_campus());
    }
    parse(&response.body, school_id)
}

fn parse(body: &[u8], school_id: &str) -> Result<OnlineInfo> {
    let text = std::str::from_utf8(body).map_err(|_| changed())?;
    let (start, end) = (text.find('{'), text.rfind('}'));
    let (Some(start), Some(end)) = (start, end) else {
        return Err(changed());
    };
    if end < start {
        return Err(changed());
    }
    let payload: Value = serde_json::from_str(&text[start..=end]).map_err(|_| changed())?;
    match payload.get("error").and_then(Value::as_str) {
        Some("ok") => {}
        Some(_) => return Err(unavailable("当前设备未登录杭州校园网")),
        None => return Err(changed()),
    }
    let account = payload
        .get("user_name")
        .and_then(Value::as_str)
        .map_or("", str::trim);
    if !account.eq_ignore_ascii_case(school_id) {
        return Err(unavailable("当前设备登录的不是你的杭州校园网账号"));
    }
    let balance = payload
        .get("user_balance")
        .and_then(Value::as_f64)
        .filter(|value| value.is_finite() && value.abs() < 1e12)
        .ok_or_else(changed)?;
    let used_bytes = payload
        .get("sum_bytes")
        .and_then(Value::as_u64)
        .ok_or_else(changed)?;
    let product_name = payload
        .get("products_name")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|name| !name.is_empty() && name.len() <= 128)
        .unwrap_or("杭州校园网")
        .to_owned();
    Ok(OnlineInfo {
        balance,
        used_bytes,
        product_name,
    })
}

#[track_caller]
fn not_on_campus() -> UbaaError {
    unavailable("连接杭州校园网后可查看网费")
}

#[track_caller]
fn unavailable(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamUnavailable,
        ErrorKind::Upstream,
        false,
        message,
    )
}

#[track_caller]
fn changed() -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        "杭州认证网关响应格式变化",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const ONLINE: &str = r#"ubaa({"ServerFlag":0,"error":"ok","user_name":"10000000","user_balance":25.015088,"sum_bytes":197450000000,"remain_bytes":0,"products_name":"学生","online_ip":"10.0.0.1"})"#;

    #[test]
    fn 本人在线时读取余额与已用流量() {
        let info = parse(ONLINE.as_bytes(), "10000000").unwrap();
        assert_eq!(format!("{:.2}", info.balance), "25.02");
        assert_eq!(info.product_name, "学生");
        let used = format_flow(info.used_bytes);
        assert_eq!((used.value.as_str(), used.unit.as_str()), ("197.45", "GB"));
    }

    #[test]
    fn 免费剩余为70gb减已用且不为负() {
        let cases = [
            (0, "70.00"),
            (12_340_000_000, "57.66"),
            (70_000_000_000, "0.00"),
            (197_450_000_000, "0.00"),
        ];
        for (used, remaining) in cases {
            let amount = free_remaining(used);
            assert_eq!(
                (amount.value.as_str(), amount.unit.as_str()),
                (remaining, "GB")
            );
        }
    }

    #[test]
    fn 计费剩余按余额乘4且不读remain_bytes() {
        // 手机上网关的 remain_bytes 为 0，结果仍按余额计算。
        let mut info = parse(ONLINE.as_bytes(), "10000000").unwrap();
        assert_eq!(billable_remaining(&info).value, "100.06");
        info.balance = -1.0;
        assert_eq!(billable_remaining(&info).value, "0.00");
    }

    #[test]
    fn 流量按1000进制与认证页一致() {
        let cases = [
            (0, "0", "B"),
            (999, "999.00", "B"),
            (1500, "1.50", "KB"),
            (4_811_842, "4.81", "MB"),
        ];
        for (bytes, value, unit) in cases {
            let amount = format_flow(bytes);
            assert_eq!((amount.value.as_str(), amount.unit.as_str()), (value, unit));
        }
    }

    #[test]
    fn 他人账号或未在线都不显示余额() {
        let other = parse(ONLINE.as_bytes(), "10000001").unwrap_err();
        assert!(other.message.contains("不是你的"));
        let offline = parse(
            br#"ubaa({"error":"not_online_error","online_ip":"10.0.0.1"})"#,
            "10000000",
        )
        .unwrap_err();
        assert!(offline.message.contains("未登录"));
        assert_eq!(
            parse(b"Internal Server Error", "10000000")
                .unwrap_err()
                .code,
            ErrorCode::UpstreamChanged
        );
    }
}
