//! SPOC 参数的冻结 AES-CFB/Base64 编码。

use aes::Aes128;
use aes::cipher::{BlockEncrypt, KeyInit, generic_array::GenericArray};
use base64::Engine as _;

pub(crate) fn encrypt_param(plain: &str) -> String {
    let mut bytes = plain.as_bytes().to_vec();
    let padding = (16 - bytes.len() % 16) % 16;
    bytes.resize(bytes.len() + padding, 0);
    let cipher = Aes128::new_from_slice(b"inco12345678ocni").expect("static AES key");
    let mut previous = *b"ocni12345678inco";
    for chunk in bytes.chunks_exact_mut(16) {
        for (byte, prior) in chunk.iter_mut().zip(previous) {
            *byte ^= prior;
        }
        let mut block = GenericArray::clone_from_slice(chunk);
        cipher.encrypt_block(&mut block);
        chunk.copy_from_slice(&block);
        previous.copy_from_slice(&block);
    }
    base64::engine::general_purpose::STANDARD.encode(bytes)
}
