/// P0 只用于证明 Dart、FRB 与 Rust 动态库真实连通。
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_hello() -> String {
    "UBAA FRB 2.13.0 ready".to_owned()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // 初始化 FRB 的平台日志与 panic 支持；业务日志仍遵守 Core 脱敏规则。
    flutter_rust_bridge::setup_default_user_utils();
}

#[cfg(test)]
mod tests {
    #[test]
    fn p0_hello_只返回固定非敏感版本信息() {
        assert_eq!(super::bridge_hello(), "UBAA FRB 2.13.0 ready");
    }
}
