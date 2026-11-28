//! 网费自助首页的只读流量表。
use super::{NETWORK_HOME, Service, activate, get, now, parser, persist, status};
use crate::domain::NetworkUsage;
use crate::error::Result;
use crate::runtime::ClientRuntime;

pub(crate) async fn get_usage(runtime: &mut ClientRuntime) -> Result<NetworkUsage> {
    // 流量查询不读门户资料，只按登录学工号的院系代码识别杭州学生；北京学生路径不变。
    let account = runtime.account_name().map(str::to_owned);
    if super::hangzhou_card::is_hangzhou(None, account.as_deref()) {
        let fetched_at = now(runtime)?;
        return super::hangzhou_network::usage(runtime, account.as_deref(), fetched_at).await;
    }
    let mut response = get(
        runtime,
        NETWORK_HOME,
        false,
        "https://zfw.buaa.edu.cn/pay/card",
    )
    .await?;
    if matches!(response.status, 301 | 302 | 303 | 307 | 308 | 401 | 403) {
        activate(runtime, Service::Network).await?;
        response = get(
            runtime,
            NETWORK_HOME,
            false,
            "https://zfw.buaa.edu.cn/pay/card",
        )
        .await?;
    }
    status(&response)?;
    let text = std::str::from_utf8(&response.body).map_err(|_| parser::invalid())?;
    let result = parser::traffic(text, now(runtime)?)?;
    persist(runtime)?;
    Ok(result)
}
