//! 图书馆预约请求的冻结加密编码。

use aes::Aes128;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};

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
    let cipher = Aes128::new_from_slice(key).map_err(|_| {
        UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "图书馆 AES 密钥无效",
        )
    })?;
    let pad = 16 - (plain.len() % 16);
    let mut padded = plain;
    padded.extend(std::iter::repeat_n(u8::try_from(pad).unwrap_or(16), pad));
    let mut previous = *b"ZZWBKJ_ZHIHUAWEI";
    let mut encrypted = Vec::with_capacity(padded.len());
    for chunk in padded.chunks_exact(16) {
        let mut block = [0_u8; 16];
        for (index, byte) in chunk.iter().enumerate() {
            block[index] = *byte ^ previous[index];
        }
        cipher.encrypt_block(GenericArray::from_mut_slice(&mut block));
        encrypted.extend_from_slice(&block);
        previous = block;
    }
    Ok(STANDARD.encode(encrypted))
}
