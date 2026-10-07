//! 场馆验证码凭据的冻结 AES-ECB/PKCS#7 编码。

use aes::{Aes128, Aes192, Aes256};
use base64::Engine as _;
use cipher::{BlockEncryptMut, KeyInit, block_padding::Pkcs7};

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
    macro_rules! encrypt {
        ($aes:ty) => {
            ecb::Encryptor::<$aes>::new_from_slice(key)
                .map_err(|_| error("验证码密钥长度无效"))?
                .encrypt_padded_vec_mut::<Pkcs7>(plain.as_bytes())
        };
    }
    let bytes = match key.len() {
        16 => encrypt!(Aes128),
        24 => encrypt!(Aes192),
        32 => encrypt!(Aes256),
        _ => return Err(error("验证码密钥长度无效")),
    };
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
