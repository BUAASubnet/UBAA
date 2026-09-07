#[path = "transport_logging.rs"]
mod transport_logging;

/// P0 只用于证明 Dart、FRB 与 Rust 动态库真实连通。
#[flutter_rust_bridge::frb(sync)]
pub fn bridge_hello() -> String {
    "UBAA FRB 2.13.0 ready".to_owned()
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // 初始化 FRB 的平台日志与 panic 支持；业务日志仍遵守 Core 脱敏规则。
    flutter_rust_bridge::setup_default_user_utils();
    transport_logging::install_default();
}

#[cfg(test)]
mod tests {
    use std::process::{Command, Output};

    const CHILD_MARKER: &str = "UBAA_BRIDGE_LOG_CHILD";

    fn run_ignored_child(name: &str) -> Output {
        Command::new(std::env::current_exe().expect("应能定位当前测试程序"))
            .arg(name)
            .arg("--exact")
            .arg("--ignored")
            .arg("--nocapture")
            .env(CHILD_MARKER, "1")
            .output()
            .expect("应能启动隔离测试子进程")
    }

    #[test]
    fn p0_hello_只返回固定非敏感版本信息() {
        assert_eq!(super::bridge_hello(), "UBAA FRB 2.13.0 ready");
    }

    #[test]
    fn bridge_initialization_只接收安全传输_target() {
        let output = run_ignored_child("api::simple::tests::bridge_logging_filter_child");
        assert!(output.status.success(), "隔离子进程必须成功退出");
        let stderr = String::from_utf8(output.stderr).expect("日志必须是 UTF-8");

        assert!(stderr.contains("HTTP 传输失败"), "应接收安全传输事件");
        assert!(stderr.contains("stage=\"send\""));
        assert!(stderr.contains("reason=\"timeout\""));
        assert!(stderr.contains("elapsed_ms=7"));
        for forbidden in [
            "core-secret",
            "third-party-secret",
            "same-target-secret",
            "ubaa::cgyy",
        ] {
            assert!(!stderr.contains(forbidden), "Bridge 日志泄露了 {forbidden}");
        }
    }

    #[test]
    fn bridge_initialization_保留宿主已有_subscriber() {
        let output = run_ignored_child("api::simple::tests::bridge_host_subscriber_child");
        assert!(output.status.success(), "隔离子进程必须成功退出");
        let stderr = String::from_utf8(output.stderr).expect("日志必须是 UTF-8");
        assert!(stderr.contains("host-subscriber-marker"));
    }

    #[test]
    #[ignore = "由父测试在子进程中隔离全局 subscriber"]
    fn bridge_logging_filter_child() {
        if std::env::var_os(CHILD_MARKER).is_none() {
            return;
        }
        super::init_app();
        tracing::debug!(
            target: "ubaa::transport",
            stage = "send",
            reason = "timeout",
            elapsed_ms = 7_u64,
            "HTTP 传输失败"
        );
        tracing::debug!(
            target: "ubaa::cgyy",
            detail = "core-secret",
            "其它 Core 事件"
        );
        tracing::debug!(
            target: "third_party",
            detail = "third-party-secret",
            "第三方事件"
        );
        tracing::debug!(
            target: "ubaa::transport",
            stage = "receive",
            reason = "body",
            elapsed_ms = 9_u64,
            detail = "same-target-secret",
            "带额外字段的事件"
        );
    }

    #[test]
    #[ignore = "由父测试在子进程中隔离全局 subscriber"]
    fn bridge_host_subscriber_child() {
        if std::env::var_os(CHILD_MARKER).is_none() {
            return;
        }
        tracing::subscriber::set_global_default(
            tracing_subscriber::fmt()
                .without_time()
                .with_ansi(false)
                .with_writer(std::io::stderr)
                .finish(),
        )
        .expect("隔离子进程应能安装宿主 subscriber");
        super::init_app();
        tracing::warn!(target: "host-owned", "host-subscriber-marker");
    }
}
