//! `WebVPN` 网关拥有独立 CAS 会话；登录不通过任一业务网站激活网关。
use crate::domain::ConnectionMode;
use crate::error::Result;
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

const LOGIN: &str =
    "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fd.buaa.edu.cn%2Flogin%3Fcas_login%3Dtrue";
const ROOT: &str = "https://d.buaa.edu.cn/";

pub(super) async fn activate(runtime: &mut ClientRuntime) -> Result<()> {
    if runtime.mode() != ConnectionMode::WebVpn {
        return Ok(());
    }
    let mut current = runtime.url(LOGIN)?;
    for _ in 0..super::MAX_REDIRECTS {
        let response = runtime.request(HttpRequest::get(&current)).await?;
        let direct = crate::connection::from_webvpn_url(&current)?;
        let parsed =
            url::Url::parse(&direct).map_err(|_| super::upstream_changed("网关认证地址无效"))?;
        if super::is_redirect(response.status) {
            // token 回调已建立网关 Cookie，后续只验证网关本身，不请求此前保存的业务地址。
            if parsed.host_str() == Some("d.buaa.edu.cn") && parsed.path() == "/token-login" {
                current = ROOT.into();
                continue;
            }
            let location = response
                .header_first("location")
                .ok_or_else(|| super::upstream_changed("网关认证缺少跳转地址"))?;
            current =
                crate::connection::resolve_redirect(&response.final_url, location, runtime.mode())?;
            let target = crate::connection::from_webvpn_url(&current)?;
            if !url::Url::parse(&target).is_ok_and(|url| {
                matches!(url.host_str(), Some("sso.buaa.edu.cn" | "d.buaa.edu.cn"))
            }) {
                return Err(super::upstream_changed("网关认证跳转到未声明服务"));
            }
            if url::Url::parse(&target).is_ok_and(|url| url.host_str() == Some("d.buaa.edu.cn")) {
                // 网关返回的自指包装路径参与其票据交换，校验通过后保留原 Location。
                let outer = url::Url::parse(&response.final_url)
                    .and_then(|base| base.join(location))
                    .map_err(|_| super::upstream_changed("网关回调地址无效"))?;
                current = outer.to_string();
            }
            continue;
        }
        if response.status == 200
            && direct == ROOT
            && crate::upstream::extract_execution(&super::body_text(&response)).is_none()
        {
            return Ok(());
        }
        return Err(super::status_error(
            response.status,
            "WebVPN 网关认证未完成",
        ));
    }
    Err(super::upstream_changed("网关认证重定向次数超过上限"))
}
