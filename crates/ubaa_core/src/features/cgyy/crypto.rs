//! 研讨室验证码凭据的冻结 AES-ECB/PKCS#7 编码。

use aes::{Aes128, Aes192, Aes256};
use base64::Engine as _;
use cipher::{BlockModeEncrypt, KeyInit, block_padding::Pkcs7};

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

/// 杭州：位移来自用户拖动，可为小数；按网页 `JSON.stringify({x, y: 5})` 的数字格式编码。
pub(crate) fn build_captcha_solution_at(
    secret_key: &str,
    token: &str,
    move_distance: f64,
) -> Result<(String, String)> {
    let x = js_number(move_distance);
    let point_json = format!(r#"{{"x":{x},"y":5}}"#);
    let verification_plain = format!("{token}---{point_json}");
    Ok((
        encrypt_captcha_text(&point_json, secret_key)?,
        encrypt_captcha_text(&verification_plain, secret_key)?,
    ))
}

/// 与 JavaScript `Number#toString` 一致：整数不带小数点，其余用最短往返表示。
fn js_number(value: f64) -> String {
    if value.fract() == 0.0 && value.abs() < 1e15 {
        #[allow(clippy::cast_possible_truncation)]
        let integer = value as i64;
        integer.to_string()
    } else {
        value.to_string()
    }
}

fn encrypt_captcha_text(plain: &str, secret_key: &str) -> Result<String> {
    let key = secret_key.as_bytes();
    macro_rules! encrypt {
        ($aes:ty) => {
            ecb::Encryptor::<$aes>::new_from_slice(key)
                .map_err(|_| error("验证码密钥长度无效"))?
                .encrypt_padded_vec::<Pkcs7>(plain.as_bytes())
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

#[track_caller]
fn error(message: &str) -> UbaaError {
    UbaaError::new(
        ErrorCode::UpstreamChanged,
        ErrorKind::Upstream,
        false,
        message,
    )
}

#[cfg(test)]
mod hangzhou_tests {
    use super::js_number;

    #[test]
    fn 滑块位移数字格式与网页一致() {
        assert_eq!(js_number(123.0), "123");
        assert_eq!(js_number(123.5), "123.5");
        assert_eq!(js_number(0.0), "0");
    }
}
