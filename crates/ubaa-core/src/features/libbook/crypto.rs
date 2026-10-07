//! 图书馆预约请求的冻结加密编码。

use aes::Aes128;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use cipher::{BlockEncryptMut, KeyIvInit, block_padding::Pkcs7};

use crate::domain::LibBookReserveRequest;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

#[derive(serde::Serialize)]
pub(super) struct EncryptedReserveBody<'a> {
    #[serde(rename = "seat_id")]
    pub(super) seat_id: &'a str,
    pub(super) segment: &'a str,
    pub(super) day: &'a str,
    #[serde(rename = "start_time")]
    pub(super) start_time: &'a str,
    #[serde(rename = "end_time")]
    pub(super) end_time: &'a str,
}

pub(super) fn encrypt_reserve_request(request: &LibBookReserveRequest) -> Result<String> {
    let digits: String = request.day.chars().filter(char::is_ascii_digit).collect();
    if digits.len() != 8 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "预约日期无效",
        ));
    }
    let key_text = format!("{digits}{}", digits.chars().rev().collect::<String>());
    let key = key_text.as_bytes();
    let plain = serde_json::to_vec(&EncryptedReserveBody {
        seat_id: &request.seat_id,
        segment: &request.segment,
        day: &request.day,
        start_time: "",
        end_time: "",
    })
    .map_err(|_| {
        UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "图书馆预约参数无效",
        )
    })?;
    let cipher =
        cbc::Encryptor::<Aes128>::new_from_slices(key, b"ZZWBKJ_ZHIHUAWEI").map_err(|_| {
            UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "图书馆 AES 密钥无效",
            )
        })?;
    let encrypted = cipher.encrypt_padded_vec_mut::<Pkcs7>(&plain);
    Ok(STANDARD.encode(encrypted))
}
