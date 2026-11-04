//! 冻结 Cloud 模块的协议实现，业务 Token 与原始响应仅在 Core 内流动。
pub(crate) mod auth;
pub(crate) mod download;
pub(crate) mod parse;
pub(crate) mod read;
pub(crate) mod share;
#[cfg(test)]
mod tests;
pub(crate) mod transfer;
pub(crate) mod upload;
pub(crate) mod wire;

#[cfg(test)]
mod auth_tests;
