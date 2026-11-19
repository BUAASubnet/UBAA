//! 卡站点信封、充值与收银台会话。
#![allow(clippy::missing_errors_doc)]

use aes::Aes128;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use cipher::{BlockModeDecrypt, BlockModeEncrypt, KeyInit, block_padding::Pkcs7};
use rand::RngExt;
use serde_json::Value;

use crate::error::{Result, UbaaError};

const KEY_CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

fn invalid() -> UbaaError {
    UbaaError::upstream_changed("校园卡响应不符合已验证的格式")
}

/// 前端 handleKey：先按 10 位移位，再整体反转；解码是它的逆过程。
fn handle_key(value: &str, encode: bool) -> String {
    let chars: Vec<char> = value.chars().collect();
    if encode {
        let shifted: String = chars[10..].iter().chain(chars[..10].iter()).collect();
        return shifted.chars().rev().collect();
    }
    let reversed: Vec<char> = chars.iter().rev().copied().collect();
    let mut out: String = reversed[6..].iter().collect();
    out.extend(&reversed[..6]);
    out
}

pub(super) fn random_key() -> String {
    let mut rng = rand::rng();
    (0..16)
        .map(|_| char::from(KEY_CHARS[rng.random_range(0..KEY_CHARS.len())]))
        .collect()
}

/// 生成 `datajson`：密钥置换前缀 + AES-128-ECB/PKCS7 的 Base64 密文。
pub(super) fn seal(payload: &Value) -> Result<String> {
    let key = random_key();
    let plain = serde_json::to_vec(payload).map_err(|_| invalid())?;
    let mut buffer = plain;
    let length = buffer.len();
    buffer.resize(length + 16, 0);
    let cipher = ecb::Encryptor::<Aes128>::new_from_slice(key.as_bytes()).map_err(|_| invalid())?;
    let encrypted = cipher
        .encrypt_padded::<Pkcs7>(&mut buffer, length)
        .map_err(|_| invalid())?;
    Ok(format!(
        "{}{}",
        handle_key(&key, true),
        STANDARD.encode(encrypted)
    ))
}

/// 解开响应 `datajson`；密钥由前缀反推。
pub(super) fn open(blob: &str) -> Result<Value> {
    if blob.len() < 17 || !blob.is_char_boundary(16) {
        return Err(invalid());
    }
    let key = handle_key(&blob[..16], false);
    let mut raw = STANDARD.decode(&blob[16..]).map_err(|_| invalid())?;
    let cipher = ecb::Decryptor::<Aes128>::new_from_slice(key.as_bytes()).map_err(|_| invalid())?;
    let plain = cipher
        .decrypt_padded::<Pkcs7>(&mut raw)
        .map_err(|_| invalid())?;
    serde_json::from_slice(plain).map_err(|_| invalid())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 密钥置换可逆() {
        for key in ["AbCdEfGh12345678", "zzzzzzzzzzzzzzzz", "0123456789abcdef"] {
            assert_eq!(handle_key(&handle_key(key, true), false), key);
        }
    }

    #[test]
    fn 信封往返保持字段() {
        for _ in 0..64 {
            let payload = serde_json::json!({
                "openid": "A1B2C3D4E5F6",
                "idserial": "25375059",
                "txamt": "100",
            });
            let sealed = seal(&payload).expect("封装");
            assert!(sealed.len() > 16);
            assert_eq!(open(&sealed).expect("解封"), payload);
        }
    }

    #[test]
    fn 非法信封被拒绝() {
        assert!(open("").is_err());
        assert!(open("short").is_err());
        assert!(open("!!!!!!!!!!!!!!!!not-base64").is_err());
    }
}
