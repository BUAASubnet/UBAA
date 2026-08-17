//! Direct/WebVPN URL policy and auditable redirect resolution.

use std::fmt::Write as _;

use aes::Aes128;
use aes::cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};
use url::Url;

use crate::domain::ConnectionMode;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

const WEBVPN_HOST: &str = "d.buaa.edu.cn";
const WEBVPN_KEY: &[u8; 16] = b"wrdvpnisthebest!";

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

/// Check whether an absolute authentication URL uses a verified host.
#[must_use]
pub fn is_allowed_auth_host(url: &str) -> bool {
    Url::parse(url)
        .ok()
        .and_then(|parsed| {
            parsed
                .host_str()
                .map(|host| AuthHostPolicy::default().allows(host))
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
