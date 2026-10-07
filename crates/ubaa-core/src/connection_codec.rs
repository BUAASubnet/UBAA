//! `WebVPN` 主机段的冻结 AES-CFB 编解码。

use aes::Aes128;
use cipher::{AsyncStreamCipher, KeyIvInit};

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

pub(crate) const WEBVPN_KEY: &[u8; 16] = b"wrdvpnisthebest!";

pub(crate) fn encrypt_host(host: &str) -> String {
    let mut ciphertext = host.as_bytes().to_vec();
    cfb_mode::Encryptor::<Aes128>::new(WEBVPN_KEY.into(), WEBVPN_KEY.into())
        .encrypt(&mut ciphertext);
    format!("{}{}", hex::encode(WEBVPN_KEY), hex::encode(ciphertext))
}

pub(crate) fn decrypt_host(encoded: &str) -> Result<String> {
    if !encoded.is_ascii() || encoded.len() < 32 || !encoded.len().is_multiple_of(2) {
        return Err(protocol_error("WebVPN 主机编码无效"));
    }
    let iv = hex::decode(&encoded[..32]).map_err(|_| protocol_error("WebVPN IV 无效"))?;
    let mut plaintext =
        hex::decode(&encoded[32..]).map_err(|_| protocol_error("WebVPN 密文无效"))?;
    cfb_mode::Decryptor::<Aes128>::new_from_slices(WEBVPN_KEY, &iv)
        .map_err(|_| protocol_error("WebVPN IV 无效"))?
        .decrypt(&mut plaintext);
    String::from_utf8(plaintext).map_err(|_| protocol_error("WebVPN 主机不是 UTF-8"))
}

fn protocol_error(message: impl Into<String>) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}
