//! Direct/WebVPN URL policy and auditable redirect resolution.
#![allow(
    clippy::missing_errors_doc,
    clippy::map_unwrap_or,
    clippy::duration_suboptimal_units
)]

use std::fmt::Write as _;
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use aes::Aes128;
use aes::cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};
use serde::Serialize;
use url::Url;

use crate::config::{FeatureRouteConfig, RouteConfig};
use crate::domain::{ConnectionMode, ReadonlyFeature, RoutePolicy};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

const WEBVPN_HOST: &str = "d.buaa.edu.cn";
const WEBVPN_KEY: &[u8; 16] = b"wrdvpnisthebest!";
const GATEWAY_HOST: &str = "gw.buaa.edu.cn";
const GATEWAY_PORT: u16 = 80;
const DEFAULT_GATEWAY_CACHE_TTL: Duration = Duration::from_secs(60);

/// Three-state result of probing the BUAA campus gateway.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum NetworkState {
    /// At least one resolved gateway address accepted a TCP connection.
    Campus,
    /// Resolution, address discovery, connection, or the total budget failed.
    OffCampus,
    /// The probe itself failed internally or a diagnostic probe injected this state.
    Unknown,
}

/// Injectable gateway reachability probe used by route resolution.
pub trait GatewayProbe: Send + Sync {
    /// Probe gateway TCP reachability within one total budget.
    fn probe(&self, budget: Duration) -> NetworkState;
}

/// TCP probe for `gw.buaa.edu.cn:80` without embedded campus address ranges.
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

/// Process-local gateway result cache with a sixty-second production TTL.
pub struct CachingGatewayProbe<P> {
    inner: P,
    ttl: Duration,
    cached: Mutex<Option<(Instant, NetworkState)>>,
}

impl<P> CachingGatewayProbe<P> {
    /// Construct a cache with a caller-selected TTL; production uses sixty seconds.
    #[must_use]
    pub fn new(inner: P, ttl: Duration) -> Self {
        Self {
            inner,
            ttl,
            cached: Mutex::new(None),
        }
    }

    /// Construct a cache with the contract's sixty-second TTL.
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

/// Route decision metadata safe to expose in diagnostics and JSON.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RouteDiagnostic {
    /// Gateway reachability state observed for this decision.
    pub network: NetworkState,
    /// Initial route selected by policy and matrix.
    pub initial_route: ConnectionMode,
    /// Final route after any preflight fallback.
    pub mode: ConnectionMode,
    /// Whether another ready route replaced the initial route.
    pub used_fallback: bool,
}

impl RouteDiagnostic {
    /// Construct a no-fallback diagnostic.
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

/// Resolved route plus safe diagnostics.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RouteResolution {
    /// Concrete connection route selected for the operation.
    pub mode: ConnectionMode,
    /// User policy after configuration fallback.
    pub policy: RoutePolicy,
    /// Safe decision metadata.
    pub diagnostic: RouteDiagnostic,
}

/// Resolve one feature's user policy using the current gateway state.
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
    let network = if policy == RoutePolicy::Auto {
        probe.probe(Duration::from_millis(500))
    } else {
        NetworkState::Unknown
    };
    let row = FeatureRouteConfig::for_feature(feature);
    let mode = match policy {
        RoutePolicy::Direct => ConnectionMode::Direct,
        RoutePolicy::WebVpn => ConnectionMode::WebVpn,
        RoutePolicy::Auto => row.auto_route_override.unwrap_or(match network {
            NetworkState::Campus => ConnectionMode::Direct,
            NetworkState::OffCampus => ConnectionMode::WebVpn,
            NetworkState::Unknown => row.unknown_default,
        }),
    };
    Ok(RouteResolution {
        mode,
        policy,
        diagnostic: RouteDiagnostic::new(network, mode),
    })
}

/// Hosts observed in the frozen SSO/User Center authentication flow.
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
    /// Check an exact, case-insensitive authentication host.
    #[must_use]
    pub fn allows(&self, host: &str) -> bool {
        self.allowed
            .iter()
            .any(|allowed| host.eq_ignore_ascii_case(allowed))
    }
}

/// Check whether an absolute authentication URL uses an allowed scheme and verified host.
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

/// Convert a direct upstream URL to the verified BUAA `WebVPN` format.
///
/// # Errors
///
/// Returns an upstream protocol error when a parsed URL has no usable host.
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
        .map_or_else(String::new, |query| format!("?{query}"));
    let fragment = parsed
        .fragment()
        .map_or_else(String::new, |fragment| format!("#{fragment}"));
    Ok(format!(
        "https://{WEBVPN_HOST}/{protocol}/{encrypted_host}{path}{query}{fragment}"
    ))
}

/// Convert a verified `WebVPN` URL back to its direct upstream form.
///
/// # Errors
///
/// Returns an upstream protocol error when a valid gateway payload cannot be decoded.
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
        .map_or_else(String::new, |query| format!("?{query}"));
    let fragment = parsed
        .fragment()
        .map_or_else(String::new, |fragment| format!("#{fragment}"));
    Ok(format!("{authority}{path}{query}{fragment}"))
}

/// Resolve one manual redirect while applying the current connection strategy.
///
/// # Errors
///
/// Returns a permission or upstream protocol error for malformed or unverified redirects.
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

fn encrypt_host(host: &str) -> String {
    let plaintext = host.as_bytes();
    let mut padded = plaintext.to_vec();
    padded.resize(plaintext.len().div_ceil(16) * 16, b'0');
    let ciphertext = cfb_encrypt(&padded, WEBVPN_KEY, WEBVPN_KEY);
    let cipher_hex = hex(&ciphertext);
    format!("{}{}", hex(WEBVPN_KEY), &cipher_hex[..plaintext.len() * 2])
}

fn decrypt_host(encoded: &str) -> Result<String> {
    if encoded.len() < 32 || !encoded.len().is_multiple_of(2) {
        return Err(protocol_error("invalid WebVPN host payload"));
    }
    let iv = decode_hex(&encoded[..32]).ok_or_else(|| protocol_error("invalid WebVPN IV"))?;
    let mut cipher_hex = encoded[32..].to_string();
    while !cipher_hex.len().is_multiple_of(32) {
        cipher_hex.push('0');
    }
    let ciphertext =
        decode_hex(&cipher_hex).ok_or_else(|| protocol_error("invalid WebVPN ciphertext"))?;
    let plaintext = cfb_decrypt(&ciphertext, WEBVPN_KEY, &iv);
    let length = encoded.len() / 2 - 16;
    String::from_utf8(plaintext.into_iter().take(length).collect())
        .map_err(|_| protocol_error("WebVPN host is not UTF-8"))
}

fn cfb_encrypt(input: &[u8], key: &[u8; 16], iv: &[u8]) -> Vec<u8> {
    cfb_crypt(input, key, iv, true)
}

fn cfb_decrypt(input: &[u8], key: &[u8; 16], iv: &[u8]) -> Vec<u8> {
    cfb_crypt(input, key, iv, false)
}

fn cfb_crypt(input: &[u8], key: &[u8; 16], iv: &[u8], encrypt: bool) -> Vec<u8> {
    let cipher = Aes128::new(GenericArray::from_slice(key));
    let mut feedback = [0_u8; 16];
    feedback.copy_from_slice(iv);
    let mut output = Vec::with_capacity(input.len());
    for chunk in input.chunks(16) {
        let mut stream = GenericArray::clone_from_slice(&feedback);
        cipher.encrypt_block(&mut stream);
        let mut next_feedback = [0_u8; 16];
        for (index, value) in chunk.iter().enumerate() {
            let transformed = *value ^ stream[index];
            output.push(transformed);
            next_feedback[index] = if encrypt { transformed } else { *value };
        }
        if chunk.len() < 16 {
            next_feedback[chunk.len()..].copy_from_slice(&feedback[chunk.len()..]);
        }
        feedback = next_feedback;
    }
    output
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().fold(
        String::with_capacity(bytes.len() * 2),
        |mut output, byte| {
            let _ = write!(output, "{byte:02x}");
            output
        },
    )
}

fn decode_hex(value: &str) -> Option<Vec<u8>> {
    if !value.len().is_multiple_of(2) {
        return None;
    }
    (0..value.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&value[index..index + 2], 16).ok())
        .collect()
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
