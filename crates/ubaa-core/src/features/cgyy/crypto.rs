//! 场馆验证码凭据的冻结 AES-ECB/PKCS#7 编码。

use aes::{Aes128, Aes192, Aes256};
use base64::Engine as _;
use cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

pub(crate) fn build_captcha_solution(
    secret_key: &str,
    token: &str,
    move_distance: u32,
) -> Result<(String, String)> {
    let point_json = format!(r#"{{"x":{move_distance},"y":5}}"#);
    let verification_plain = format!("{token}---{point_json}");
    Ok((
        encrypt_captcha_text(&point_json, secret_key)?,
        encrypt_captcha_text(&verification_plain, secret_key)?,
    ))
}

fn encrypt_captcha_text(plain: &str, secret_key: &str) -> Result<String> {
    let key = secret_key.as_bytes();
    if !matches!(key.len(), 16 | 24 | 32) {
        return Err(error("验证码密钥长度无效"));
    }
    let padding = 16 - (plain.len() % 16);
    let mut bytes = plain.as_bytes().to_vec();
    let padding = u8::try_from(padding).map_err(|_| error("验证码填充长度无效"))?;
    bytes.resize(bytes.len() + usize::from(padding), padding);
    for block in bytes.chunks_exact_mut(16) {
        match key.len() {
            16 => Aes128::new(GenericArray::from_slice(key))
                .encrypt_block(GenericArray::from_mut_slice(block)),
            24 => Aes192::new(GenericArray::from_slice(key))
                .encrypt_block(GenericArray::from_mut_slice(block)),
            _ => Aes256::new(GenericArray::from_slice(key))
                .encrypt_block(GenericArray::from_mut_slice(block)),
        }
    }
    Ok(base64::engine::general_purpose::STANDARD.encode(bytes))
}

fn error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}
