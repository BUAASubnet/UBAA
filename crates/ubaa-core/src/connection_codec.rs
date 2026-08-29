//! `WebVPN` 主机段的冻结 AES-CFB 编解码。

use std::fmt::Write as _;

use aes::Aes128;
use aes::cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

pub(crate) const WEBVPN_KEY: &[u8; 16] = b"wrdvpnisthebest!";

pub(crate) fn encrypt_host(host: &str) -> String {
    let plaintext = host.as_bytes();
    let mut padded = plaintext.to_vec();
    padded.resize(plaintext.len().div_ceil(16) * 16, b'0');
    let ciphertext = cfb_crypt(&padded, WEBVPN_KEY, WEBVPN_KEY, true);
    let cipher_hex = hex(&ciphertext);
    format!("{}{}", hex(WEBVPN_KEY), &cipher_hex[..plaintext.len() * 2])
}

pub(crate) fn decrypt_host(encoded: &str) -> Result<String> {
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
    let plaintext = cfb_crypt(&ciphertext, WEBVPN_KEY, &iv, false);
    let length = encoded.len() / 2 - 16;
    String::from_utf8(plaintext.into_iter().take(length).collect())
        .map_err(|_| protocol_error("WebVPN host is not UTF-8"))
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
