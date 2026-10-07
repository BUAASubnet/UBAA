//! SPOC 参数的冻结 AES-128-CBC/NoPadding、零填充与 Base64 编码。

use aes::Aes128;
use base64::Engine as _;
use cipher::{BlockEncryptMut, KeyIvInit, block_padding::ZeroPadding};

pub(super) fn encrypt_param(plain: &str) -> String {
    let bytes =
        cbc::Encryptor::<Aes128>::new(b"inco12345678ocni".into(), b"ocni12345678inco".into())
            .encrypt_padded_vec_mut::<ZeroPadding>(plain.as_bytes());
    base64::engine::general_purpose::STANDARD.encode(bytes)
}
