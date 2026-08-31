pub mod api;
// FRB 生成的 FFI 编解码不可避免地包含 unsafe 与机械类型转换；例外只作用于该生成模块。
#[allow(unsafe_code, clippy::all, clippy::pedantic)]
mod frb_generated;
