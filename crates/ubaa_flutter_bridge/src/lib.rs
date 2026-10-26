pub mod api;
// 仅JNI导出符号需要unsafe属性，函数参数由JVM提供，业务层不接收原始指针。
#[cfg(target_os = "android")]
#[allow(unsafe_code)]
mod android_tls;
// FRB 生成的 FFI 编解码不可避免地包含 unsafe 与机械类型转换；例外只作用于该生成模块。
#[allow(unsafe_code, clippy::all, clippy::pedantic)]
mod frb_generated;
