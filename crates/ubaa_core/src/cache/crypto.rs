//! 载荷和查询一起认证加密，数据库索引不暴露精确查询正文。
use super::{CacheError, CacheResult};
use aes_gcm::{
    Aes256Gcm, KeyInit, Nonce,
    aead::{Aead, Payload},
};
use hmac::{Hmac, Mac};
use rand::{TryRng, rngs::SysRng};
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

pub(crate) struct Crypto {
    key: CacheKey,
}
impl Crypto {
    pub fn new(key: CacheKey) -> Self {
        Self { key }
    }
    pub fn index<T: Serialize>(&self, value: &T) -> CacheResult<Vec<u8>> {
        let bytes =
            Zeroizing::new(serde_json::to_vec(value).map_err(|_| CacheError::InvalidInput)?);
        let mut mac = <Hmac<Sha256> as KeyInit>::new_from_slice(self.key.0.as_ref())
            .map_err(|_| CacheError::Unavailable)?;
        mac.update(b"ubaa.cache.index.v1\0");
        mac.update(&bytes);
        Ok(mac.finalize().into_bytes().to_vec())
    }
    pub fn seal<T: Serialize>(&self, value: &T, aad: &[u8]) -> CacheResult<Vec<u8>> {
        let bytes =
            Zeroizing::new(serde_json::to_vec(value).map_err(|_| CacheError::InvalidInput)?);
        let mut nonce = [0; 12];
        SysRng
            .try_fill_bytes(&mut nonce)
            .map_err(|_| CacheError::Unavailable)?;
        let cipher =
            Aes256Gcm::new_from_slice(self.key.0.as_ref()).map_err(|_| CacheError::Unavailable)?;
        let encrypted = cipher
            .encrypt(&Nonce::from(nonce), Payload { msg: &bytes, aad })
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
                    bytes[..12].try_into().map_err(|_| CacheError::Corrupt)?,
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 读取既有格式的密文并保持索引一致() {
        let crypto = Crypto::new(CacheKey::new([7; 32]));
        let value = serde_json::json!({"value": "缓存"});
        // 独立 AES-GCM 实现生成，顺序为 nonce、密文和认证标签。
        let sealed = hex::decode(
            "0303030303030303030303035edcd562365d3b604062a4e078b25294cf41c0a2807ce8d4fa711c0c15f368bded19",
        ).unwrap();
        assert_eq!(
            crypto
                .open::<serde_json::Value>(&sealed, b"ubaa.cache.test")
                .unwrap(),
            value,
        );
        assert_eq!(
            hex::encode(crypto.index(&value).unwrap()),
            "af655fbda2a3e362c1b213ae076a586ee6dcaa3b39446b29e9c113a841bfd223",
        );
    }
}
