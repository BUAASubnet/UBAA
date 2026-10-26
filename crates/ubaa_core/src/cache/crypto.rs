//! 载荷和查询一起认证加密，数据库索引不暴露精确查询正文。
use super::{CacheError, CacheResult};
use aes_gcm::{
    Aes256Gcm, KeyInit, Nonce,
    aead::{Aead, Payload},
};
use hmac::{Hmac, Mac};
use rand::{RngCore, rngs::OsRng};
use serde::{Serialize, de::DeserializeOwned};
use sha2::Sha256;
use zeroize::Zeroizing;

/// 平台安全存储交付的独立 256 位数据密钥；不支持格式化或序列化。
pub struct CacheKey(Zeroizing<[u8; 32]>);
impl CacheKey {
    #[must_use]
    pub fn new(bytes: [u8; 32]) -> Self {
        Self(Zeroizing::new(bytes))
    }
}

pub(super) struct Crypto {
    key: CacheKey,
}
impl Crypto {
    pub fn new(key: CacheKey) -> Self {
        Self { key }
    }
    pub fn index<T: Serialize>(&self, value: &T) -> CacheResult<Vec<u8>> {
        let bytes =
            Zeroizing::new(serde_json::to_vec(value).map_err(|_| CacheError::InvalidInput)?);
        let mut mac = <Hmac<Sha256> as Mac>::new_from_slice(self.key.0.as_ref())
            .map_err(|_| CacheError::Unavailable)?;
        mac.update(b"ubaa.cache.index.v1\0");
        mac.update(&bytes);
        Ok(mac.finalize().into_bytes().to_vec())
    }
    pub fn seal<T: Serialize>(&self, value: &T, aad: &[u8]) -> CacheResult<Vec<u8>> {
        let bytes =
            Zeroizing::new(serde_json::to_vec(value).map_err(|_| CacheError::InvalidInput)?);
        let mut nonce = [0; 12];
        OsRng
            .try_fill_bytes(&mut nonce)
            .map_err(|_| CacheError::Unavailable)?;
        let cipher =
            Aes256Gcm::new_from_slice(self.key.0.as_ref()).map_err(|_| CacheError::Unavailable)?;
        let encrypted = cipher
            .encrypt(Nonce::from_slice(&nonce), Payload { msg: &bytes, aad })
            .map_err(|_| CacheError::Unavailable)?;
        let mut result = nonce.to_vec();
        result.extend(encrypted);
        Ok(result)
    }
    pub fn open<T: DeserializeOwned>(&self, bytes: &[u8], aad: &[u8]) -> CacheResult<T> {
        if bytes.len() < 28 {
            return Err(CacheError::Corrupt);
        }
        let cipher =
            Aes256Gcm::new_from_slice(self.key.0.as_ref()).map_err(|_| CacheError::Unavailable)?;
        let decrypted = Zeroizing::new(
            cipher
                .decrypt(
                    Nonce::from_slice(&bytes[..12]),
                    Payload {
                        msg: &bytes[12..],
                        aad,
                    },
                )
                .map_err(|_| CacheError::Corrupt)?,
        );
        serde_json::from_slice(&decrypted).map_err(|_| CacheError::Corrupt)
    }
}
