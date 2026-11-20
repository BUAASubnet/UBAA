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

/// 左移 10 位后整体反转，等价于分别反转前 10 位和后 6 位；同一置换即可还原。
fn handle_key(mut key: [u8; 16]) -> [u8; 16] {
    key[..10].reverse();
    key[10..].reverse();
    key
}

fn random_key() -> [u8; 16] {
    let mut rng = rand::rng();
    std::array::from_fn(|_| KEY_CHARS[rng.random_range(0..KEY_CHARS.len())])
}

/// 生成 `datajson`：密钥置换前缀 + AES-128-ECB/PKCS7 的 Base64 密文。
pub(super) fn seal(payload: &Value) -> Result<String> {
    let key = random_key();
    let plain = serde_json::to_vec(payload).map_err(|_| invalid())?;
    let mut buffer = plain;
    let length = buffer.len();
    buffer.resize(length + 16, 0);
    let cipher = ecb::Encryptor::<Aes128>::new_from_slice(&key).map_err(|_| invalid())?;
    let encrypted = cipher
        .encrypt_padded::<Pkcs7>(&mut buffer, length)
        .map_err(|_| invalid())?;
    let mut blob = String::with_capacity(key.len() + encrypted.len().div_ceil(3) * 4);
    blob.extend(handle_key(key).into_iter().map(char::from));
    STANDARD.encode_string(encrypted, &mut blob);
    Ok(blob)
}

/// 解开响应 `datajson`；密钥由前缀反推。
pub(super) fn open(blob: &str) -> Result<Value> {
    let (prefix, ciphertext) = blob.as_bytes().split_at_checked(16).ok_or_else(invalid)?;
    if !prefix.iter().all(u8::is_ascii_alphanumeric) || ciphertext.is_empty() {
        return Err(invalid());
    }
    let key = handle_key(prefix.try_into().map_err(|_| invalid())?);
    let mut raw = STANDARD.decode(ciphertext).map_err(|_| invalid())?;
    let cipher = ecb::Decryptor::<Aes128>::new_from_slice(&key).map_err(|_| invalid())?;
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
        for key in [
            *b"AbCdEfGh12345678",
            *b"zzzzzzzzzzzzzzzz",
            *b"0123456789abcdef",
        ] {
            assert_eq!(handle_key(handle_key(key)), key);
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

    #[test]
    fn 恶意多字节前缀返回格式错误而非崩溃() {
        let error = open("🀀🀀🀀🀀YWJjZA==").unwrap_err();
        assert_eq!(error.code, crate::error::ErrorCode::UpstreamChanged);
    }
}
