//! 网费自助首页的只读流量表。
use super::{NETWORK_HOME, Service, activate, get, now, parser, persist, status};
use crate::domain::NetworkUsage;
use crate::error::Result;
use crate::runtime::ClientRuntime;

pub(crate) async fn get_usage(runtime: &mut ClientRuntime) -> Result<NetworkUsage> {
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
