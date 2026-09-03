//! 博雅请求加密与响应解密。
#![allow(clippy::missing_errors_doc)]

use aes::Aes128;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use cipher::{BlockDecryptMut, BlockEncryptMut, KeyInit, block_padding::Pkcs7};
use rand::Rng;
use rsa::{Pkcs1v15Encrypt, RsaPublicKey, pkcs8::DecodePublicKey};
use sha1::{Digest, Sha1};

use super::error;
use crate::error::Result;

const RSA_PUBLIC_KEY_BASE64: &str = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDlHMQ3B5GsWnCe7Nlo1YiG/YmHdlOiKOST5aRm4iaqYSvhvWmwcigoyWTM+8bv2+sf6nQBRDWTY4KmNV7DBk1eDnTIQo6ENA31k5/tYCLEXgjPbEjCK9spiyB62fCT6cqOhbamJB0lcDJRO6Vo1m3dy+fD0jbxfDVBBNtyltIsDQIDAQAB";
const KEY_CHARS: &[u8] = b"ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678";

pub(crate) struct EncryptedRequest {
    pub(crate) encrypted_data: String,
    pub(crate) ak: String,
    pub(crate) sk: String,
    pub(crate) ts: String,
    pub(super) aes_key: [u8; 16],
}

pub(crate) fn encrypt_request(json: &str, timestamp: i64) -> Result<EncryptedRequest> {
    let mut key = [0_u8; 16];
    let mut rng = rand::thread_rng();
    for byte in &mut key {
        *byte = KEY_CHARS[rng.gen_range(0..KEY_CHARS.len())];
    }
    encrypt_request_with_key(json, timestamp, key)
}

pub(super) fn encrypt_request_with_key(
    json: &str,
    timestamp: i64,
    key: [u8; 16],
) -> Result<EncryptedRequest> {
    let cipher = Aes128::new_from_slice(&key).map_err(|_| error("博雅 AES 密钥无效"))?;
    let mut buffer = json.as_bytes().to_vec();
    let length = buffer.len();
    buffer.resize(length + 16, 0);
    let encrypted = cipher
        .encrypt_padded_mut::<Pkcs7>(&mut buffer, length)
        .map_err(|_| error("博雅请求加密失败"))?;
    let public_der = STANDARD
        .decode(RSA_PUBLIC_KEY_BASE64)
        .map_err(|_| error("博雅 RSA 公钥无效"))?;
    let public =
        RsaPublicKey::from_public_key_der(&public_der).map_err(|_| error("博雅 RSA 公钥无效"))?;
    let digest = format!("{:x}", Sha1::digest(json.as_bytes()));
    let mut rng = rand::thread_rng();
    let ak = public
        .encrypt(&mut rng, Pkcs1v15Encrypt, &key)
        .map_err(|_| error("博雅 AES 密钥加密失败"))?;
    let sk = public
        .encrypt(&mut rng, Pkcs1v15Encrypt, digest.as_bytes())
        .map_err(|_| error("博雅摘要加密失败"))?;
    Ok(EncryptedRequest {
        encrypted_data: STANDARD.encode(encrypted),
        ak: STANDARD.encode(ak),
        sk: STANDARD.encode(sk),
        ts: timestamp.to_string(),
        aes_key: key,
    })
}

pub(crate) fn decrypt_response(value: &str, key: &[u8; 16]) -> Result<String> {
    let mut data = STANDARD
        .decode(value.trim_matches('"'))
        .map_err(|_| error("博雅响应密文无效"))?;
    let cipher = Aes128::new_from_slice(key).map_err(|_| error("博雅 AES 密钥无效"))?;
    let plain = cipher
        .decrypt_padded_mut::<Pkcs7>(&mut data)
        .map_err(|_| error("博雅响应解密失败"))?;
    String::from_utf8(plain.to_vec()).map_err(|_| error("博雅响应文本无效"))
}
