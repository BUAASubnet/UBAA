//! Direct/WebVPN 地址策略与可审计的重定向解析。
#![allow(
    clippy::missing_errors_doc,
    clippy::map_unwrap_or,
    clippy::duration_suboptimal_units
)]

use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::Serialize;
use url::Url;

use crate::config::{FeatureRouteConfig, RouteConfig};
use crate::connection_codec::{decrypt_host, encrypt_host};
use crate::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

const WEBVPN_HOST: &str = "d.buaa.edu.cn";
const GATEWAY_HOST: &str = "gw.buaa.edu.cn";
const GATEWAY_PORT: u16 = 80;
const DEFAULT_GATEWAY_CACHE_TTL: Duration = Duration::from_secs(60);

/// 探测北航校园网关得到的三态结果。
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum NetworkState {
    /// 至少一个解析出的网关地址接受了 TCP 连接。
    Campus,
    /// 域名解析、地址发现、连接或总预算失败。
    OffCampus,
    /// 探测自身发生内部失败，或诊断探测注入了该状态。
    Unknown,
}

/// 路由解析使用的可注入网关可达性探测器。
pub trait GatewayProbe: Send + Sync {
    /// 在一个总预算内探测网关 TCP 可达性。
    fn probe(&self, budget: Duration) -> NetworkState;
}

/// 探测 `gw.buaa.edu.cn:80` 的 TCP 可达性，不内置校园网地址段。
#[derive(Clone, Copy, Debug, Default)]
pub struct SystemGatewayProbe;

impl GatewayProbe for SystemGatewayProbe {
    fn probe(&self, budget: Duration) -> NetworkState {
        run_gateway_probe_worker(budget, |deadline| {
            probe_gateway_until(
                deadline,
                |host, port| (host, port).to_socket_addrs().map(Iterator::collect),
                |address, remaining| TcpStream::connect_timeout(&address, remaining).is_ok(),
                Instant::now,
            )
        })
    }
}

fn run_gateway_probe_worker<Worker>(budget: Duration, worker: Worker) -> NetworkState
where
    Worker: FnOnce(Instant) -> NetworkState + Send + 'static,
{
    if budget.is_zero() {
        return NetworkState::OffCampus;
    }
    let Some(deadline) = Instant::now().checked_add(budget) else {
        return NetworkState::Unknown;
    };
    let (sender, receiver) = std::sync::mpsc::sync_channel(1);
    let spawned = std::thread::Builder::new()
        .name("ubaa-gateway-probe".to_string())
        .spawn(move || {
            let state = worker(deadline);
            let _ = sender.send(state);
        });
    if spawned.is_err() {
        return NetworkState::Unknown;
    }

    let remaining = deadline.saturating_duration_since(Instant::now());
    if remaining.is_zero() {
        return NetworkState::OffCampus;
    }
    match receiver.recv_timeout(remaining) {
        Ok(state) => state,
        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => NetworkState::OffCampus,
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => NetworkState::Unknown,
    }
}

fn probe_gateway_until<Resolve, Connect, Clock>(
    deadline: Instant,
    resolve: Resolve,
    mut connect: Connect,
    mut now: Clock,
) -> NetworkState
where
    Resolve: FnOnce(&str, u16) -> std::io::Result<Vec<SocketAddr>>,
    Connect: FnMut(SocketAddr, Duration) -> bool,
    Clock: FnMut() -> Instant,
{
    let Ok(addresses) = resolve(GATEWAY_HOST, GATEWAY_PORT) else {
        return NetworkState::OffCampus;
    };
    for address in addresses {
        let remaining = deadline.saturating_duration_since(now());
        if remaining.is_zero() {
            return NetworkState::OffCampus;
        }
        if connect(address, remaining) {
            return NetworkState::Campus;
        }
    }
    NetworkState::OffCampus
}

/// 进程内网关结果缓存，生产 TTL 为 60 秒。
pub struct CachingGatewayProbe<P> {
    inner: P,
    ttl: Duration,
    cached: Mutex<Option<(Instant, NetworkState)>>,
}

impl<P> CachingGatewayProbe<P> {
    /// 使用调用方指定的 TTL 构造缓存；生产环境使用 60 秒。
    #[must_use]
    pub fn new(inner: P, ttl: Duration) -> Self {
        Self {
            inner,
            ttl,
            cached: Mutex::new(None),
        }
    }

    /// 使用合同规定的 60 秒 TTL 构造缓存。
    #[must_use]
    pub fn with_default_ttl(inner: P) -> Self {
        Self::new(inner, DEFAULT_GATEWAY_CACHE_TTL)
    }
}

impl<P: GatewayProbe> GatewayProbe for CachingGatewayProbe<P> {
    fn probe(&self, budget: Duration) -> NetworkState {
        let now = Instant::now();
        let Ok(mut cached) = self.cached.lock() else {
            return NetworkState::Unknown;
        };
        if let Some((at, state)) = *cached
            && now.saturating_duration_since(at) < self.ttl
        {
            return state;
        }
        let state = self.inner.probe(budget);
        *cached = Some((Instant::now(), state));
        state
    }
}

/// 可安全暴露到诊断信息和 JSON 的路线决策元数据。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RouteDiagnostic {
    /// 本次决策观察到的网关可达性状态。
    pub network: NetworkState,
    /// 根据策略和矩阵选择的初始路线。
    pub initial_route: ConnectionMode,
    /// 预检查回退后的最终路线。
    pub mode: ConnectionMode,
    /// 是否由另一条就绪路线替代了初始路线。
    pub used_fallback: bool,
}

impl RouteDiagnostic {
    /// 构造不使用回退的诊断信息。
    #[must_use]
    pub const fn new(network: NetworkState, mode: ConnectionMode) -> Self {
        Self {
            network,
            initial_route: mode,
            mode,
            used_fallback: false,
        }
    }
}

/// 已解析路线及安全诊断信息。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RouteResolution {
    /// 本次操作选择的具体连接路线。
    pub mode: ConnectionMode,
    /// 配置回退后的用户策略。
    pub policy: RoutePolicy,
    /// 安全决策元数据。
    pub diagnostic: RouteDiagnostic,
}

/// 根据当前网关状态解析一个功能的用户策略。
pub fn resolve_feature_route<P: GatewayProbe + ?Sized>(
    feature: ReadonlyFeature,
    requested: RoutePolicy,
    config: &RouteConfig,
    probe: &P,
) -> crate::error::Result<RouteResolution> {
    let policy = if requested == RoutePolicy::Auto {
        config.feature(feature)
    } else {
        requested
    };
    Ok(resolve_route(
        policy,
        FeatureRouteConfig::for_feature(feature),
        probe,
    ))
}

/// 根据有效策略和矩阵行解析唯一初始路线。
#[must_use]
pub(crate) fn resolve_route<P: GatewayProbe + ?Sized>(
    effective_policy: RoutePolicy,
    row: FeatureRouteConfig,
    probe: &P,
) -> RouteResolution {
    let network = if effective_policy == RoutePolicy::Auto {
        probe.probe(Duration::from_millis(500))
    } else {
        NetworkState::Unknown
    };
    let mode = match effective_policy {
        RoutePolicy::Direct => ConnectionMode::Direct,
        RoutePolicy::WebVpn => ConnectionMode::WebVpn,
        RoutePolicy::Auto => row.auto_route_override.unwrap_or(match network {
            NetworkState::Campus => ConnectionMode::Direct,
            NetworkState::OffCampus => ConnectionMode::WebVpn,
            NetworkState::Unknown => row.unknown_default,
        }),
    };
    RouteResolution {
        mode,
        policy: effective_policy,
        diagnostic: RouteDiagnostic::new(network, mode),
    }
}

/// 冻结 SSO/用户中心认证流程中观察到的主机。
#[derive(Clone, Debug)]
pub struct AuthHostPolicy {
    allowed: &'static [&'static str],
}

impl Default for AuthHostPolicy {
    fn default() -> Self {
        Self {
            allowed: &["sso.buaa.edu.cn", "uc.buaa.edu.cn", WEBVPN_HOST],
        }
    }
}

impl AuthHostPolicy {
    /// 检查不区分大小写的精确认证主机。
    #[must_use]
    pub fn allows(&self, host: &str) -> bool {
        self.allowed
            .iter()
            .any(|allowed| host.eq_ignore_ascii_case(allowed))
    }
}

/// 检查绝对认证地址是否使用允许的协议和已验证主机。
#[must_use]
pub fn is_allowed_auth_host(url: &str) -> bool {
    Url::parse(url)
        .ok()
        .and_then(|parsed| {
            parsed.host_str().map(|host| {
                is_allowed_auth_scheme(&parsed) && AuthHostPolicy::default().allows(host)
            })
        })
        .unwrap_or(false)
}

/// 将上游直连地址转换为已验证的北航 `WebVPN` 格式。
///
/// # Errors
///
/// 解析地址没有可用主机时返回上游协议错误。
pub fn to_webvpn_url(url: &str) -> Result<String> {
    let Ok(parsed) = Url::parse(url) else {
        return Ok(url.to_string());
    };
    if parsed
        .host_str()
        .is_some_and(|host| host.eq_ignore_ascii_case(WEBVPN_HOST))
    {
        return Ok(url.to_string());
    }
    let host = parsed
        .host_str()
        .ok_or_else(|| protocol_error("URL has no host"))?;
    let protocol = match parsed.port() {
        None => parsed.scheme().to_string(),
        Some(port)
            if (parsed.scheme() == "http" && port == 80)
                || (parsed.scheme() == "https" && port == 443) =>
        {
            parsed.scheme().to_string()
        }
        Some(port) => format!("{}-{port}", parsed.scheme()),
    };
    let encrypted_host = encrypt_host(host);
    let path = parsed.path();
    let query = parsed
        .query()
        .filter(|query| !query.is_empty())
        .map_or_else(String::new, |query| format!("?{query}"));
    let fragment = parsed
        .fragment()
        .filter(|fragment| !fragment.is_empty())
        .map_or_else(String::new, |fragment| format!("#{fragment}"));
    Ok(format!(
        "https://{WEBVPN_HOST}/{protocol}/{encrypted_host}{path}{query}{fragment}"
    ))
}

/// 将已验证的 `WebVPN` 地址还原为上游直连形式。
///
/// # Errors
///
/// 有效网关载荷无法解码时返回上游协议错误。
pub fn from_webvpn_url(url: &str) -> Result<String> {
    let Ok(parsed) = Url::parse(url) else {
        return Ok(url.to_string());
    };
    if !parsed
        .host_str()
        .is_some_and(|host| host.eq_ignore_ascii_case(WEBVPN_HOST))
    {
        return Ok(url.to_string());
    }

    let segments: Vec<&str> = parsed
        .path()
        .split('/')
        .filter(|segment| !segment.is_empty())
        .collect();
    if segments.len() < 2 {
        return Ok(url.to_string());
    }
    let (scheme, port) = segments[0]
        .split_once('-')
        .map_or((segments[0], None), |(scheme, port)| {
            (scheme, port.parse::<u16>().ok())
        });
    if scheme.is_empty() {
        return Ok(url.to_string());
    }
    let Ok(host) = decrypt_host(segments[1]) else {
        return Ok(url.to_string());
    };
    let authority = port.map_or_else(
        || format!("{scheme}://{host}"),
        |port| format!("{scheme}://{host}:{port}"),
    );
    let path = if parsed.path().ends_with('/') && segments.len() == 2 {
        "/".to_string()
    } else if segments.len() > 2 {
        format!("/{}", segments[2..].join("/"))
    } else {
        String::new()
    };
    let query = parsed
        .query()
        .filter(|query| !query.is_empty())
        .map_or_else(String::new, |query| format!("?{query}"));
    let fragment = parsed
        .fragment()
        .filter(|fragment| !fragment.is_empty())
        .map_or_else(String::new, |fragment| format!("#{fragment}"));
    Ok(format!("{authority}{path}{query}{fragment}"))
}

/// 应用当前连接策略解析一次手动重定向。
///
/// # Errors
///
/// 重定向格式错误或未验证时返回权限错误或上游协议错误。
pub fn resolve_redirect(current_url: &str, location: &str, mode: ConnectionMode) -> Result<String> {
    let current =
        Url::parse(current_url).map_err(|_| protocol_error("invalid current redirect URL"))?;
    let absolute = if location.starts_with("//") {
        format!("{}:{location}", current.scheme())
    } else {
        location.to_string()
    };
    let resolved = current
        .join(&absolute)
        .map_err(|_| protocol_error("invalid redirect Location"))?;
    if !is_allowed_auth_scheme(&resolved) {
        return Err(UbaaError::new(
            ErrorCode::PermissionDenied,
            ErrorKind::Authentication,
            false,
            "redirect scheme is not allowed",
        ));
    }
    if resolved.host_str() != Some(WEBVPN_HOST)
        && !resolved
            .host_str()
            .is_some_and(|host| AuthHostPolicy::default().allows(host))
    {
        return Err(UbaaError::new(
            ErrorCode::PermissionDenied,
            ErrorKind::Authentication,
            false,
            "redirect host is not allowed",
        ));
    }
    if mode == ConnectionMode::WebVpn && resolved.host_str() != Some(WEBVPN_HOST) {
        return to_webvpn_url(resolved.as_str());
    }
    if !is_allowed_auth_host(resolved.as_str()) {
        return Err(UbaaError::new(
            ErrorCode::PermissionDenied,
            ErrorKind::Authentication,
            false,
            "redirect host is not allowed",
        ));
    }
    Ok(resolved.to_string())
}

fn is_allowed_auth_scheme(url: &Url) -> bool {
    matches!(url.scheme(), "http" | "https")
}

fn protocol_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

#[cfg(test)]
mod gateway_probe_tests {
    use std::collections::VecDeque;
    use std::io;
    use std::net::{Ipv4Addr, SocketAddr};
    use std::time::{Duration, Instant};

    use super::{
        DEFAULT_GATEWAY_CACHE_TTL, GATEWAY_HOST, GATEWAY_PORT, NetworkState, probe_gateway_until,
        run_gateway_probe_worker,
    };

    fn test_address(port: u16) -> SocketAddr {
        SocketAddr::from((Ipv4Addr::LOCALHOST, port))
    }

    #[test]
    fn gateway_probe_uses_the_fixed_target_and_one_deadline_for_all_addresses() {
        let first = test_address(10001);
        let second = test_address(10002);
        let started = Instant::now();
        let deadline = started + Duration::from_millis(500);
        let mut times = VecDeque::from([
            started + Duration::from_millis(100),
            started + Duration::from_millis(450),
        ]);
        let mut attempts = Vec::new();

        let state = probe_gateway_until(
            deadline,
            |host, port| {
                assert_eq!(host, GATEWAY_HOST);
                assert_eq!(port, GATEWAY_PORT);
                Ok(vec![first, second])
            },
            |address, remaining| {
                attempts.push((address, remaining));
                address == second
            },
            || times.pop_front().expect("one clock value per address"),
        );

        assert_eq!(state, NetworkState::Campus);
        assert_eq!(
            attempts,
            vec![
                (first, Duration::from_millis(400)),
                (second, Duration::from_millis(50)),
            ]
        );
    }

    #[test]
    fn gateway_resolution_failure_is_off_campus() {
        let state = probe_gateway_until(
            Instant::now() + Duration::from_millis(500),
            |_, _| Err(io::Error::other("synthetic resolution failure")),
            |_, _| -> bool { panic!("connection must not be attempted") },
            Instant::now,
        );

        assert_eq!(state, NetworkState::OffCampus);
    }

    #[test]
    fn gateway_resolution_with_no_addresses_is_off_campus() {
        let state = probe_gateway_until(
            Instant::now() + Duration::from_millis(500),
            |_, _| Ok(Vec::<SocketAddr>::new()),
            |_, _| -> bool { panic!("connection must not be attempted") },
            Instant::now,
        );

        assert_eq!(state, NetworkState::OffCampus);
    }

    #[test]
    fn expired_total_budget_skips_remaining_addresses() {
        let address = test_address(10001);
        let deadline = Instant::now();
        let state = probe_gateway_until(
            deadline,
            |_, _| Ok(vec![address]),
            |_, _| -> bool { panic!("connection must not exceed the shared deadline") },
            || deadline,
        );

        assert_eq!(state, NetworkState::OffCampus);
    }

    #[test]
    fn failed_connections_to_every_address_are_off_campus() {
        let first = test_address(10001);
        let second = test_address(10002);
        let started = Instant::now();
        let mut attempts = Vec::new();
        let state = probe_gateway_until(
            started + Duration::from_millis(500),
            |_, _| Ok(vec![first, second]),
            |address, _| {
                attempts.push(address);
                false
            },
            || started,
        );

        assert_eq!(state, NetworkState::OffCampus);
        assert_eq!(attempts, vec![first, second]);
    }

    #[test]
    fn caller_timeout_is_off_campus_even_when_worker_finishes_later() {
        let state = run_gateway_probe_worker(Duration::from_millis(5), |_| {
            std::thread::sleep(Duration::from_millis(50));
            NetworkState::Campus
        });

        assert_eq!(state, NetworkState::OffCampus);
    }

    #[test]
    fn production_gateway_cache_ttl_is_sixty_seconds() {
        assert_eq!(DEFAULT_GATEWAY_CACHE_TTL, Duration::from_secs(60));
    }
}
