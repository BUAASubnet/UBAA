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
    super::app_service::install_panic_hook();
    transport_logging::install_default();
}

#[cfg(test)]
mod tests {
    use super::super::app_service::{BridgeAppServiceSurface, suppress_panic_for_test, tests};
    use std::process::{Command, Output};

    const CHILD_MARKER: &str = "UBAA_BRIDGE_LOG_CHILD";

    fn run_ignored_child(name: &str) -> Output {
        Command::new(std::env::current_exe().expect("应能定位当前测试程序"))
            .arg(name)
            .arg("--exact")
            .arg("--ignored")
            .arg("--nocapture")
            .env(CHILD_MARKER, "1")
            // 隔离子进程只检查合成数据是否入队，不运行任何请求。
            .env_remove("CI")
            .env_remove("UBAA_TELEMETRY")
            .output()
            .expect("应能启动隔离测试子进程")
    }

    #[test]
    fn p0_hello_只返回固定非敏感版本信息() {
        assert_eq!(super::bridge_hello(), "UBAA FRB 2.13.0 ready");
    }

    #[test]
    fn bridge_initialization_只接收安全传输和门控诊断() {
        let output = run_ignored_child("api::simple::tests::bridge_logging_filter_child");
        assert!(output.status.success(), "隔离子进程必须成功退出");
        let stderr = String::from_utf8(output.stderr).expect("日志必须是 UTF-8");

        assert!(stderr.contains("HTTP 传输失败"), "应接收安全传输事件");
        assert!(stderr.contains("stage=\"send\""));
        assert!(stderr.contains("reason=\"timeout\""));
        assert!(stderr.contains("elapsed_ms=7"));
        assert!(stderr.contains("无法读取应用服务门控状态，本次学校请求继续"));
        for forbidden in [
            "core-secret",
            "third-party-secret",
            "same-target-secret",
            "gate-detail-secret",
            "gate-wrong-level",
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
    fn bridge_panic_保留_frb_与宿主钩子且只交付安全位置() {
        let output = run_ignored_child("api::simple::tests::bridge_panic_chain_child");
        assert!(output.status.success(), "隔离子进程必须成功退出");
    }

    #[ignore = "由父测试在子进程中隔离全局 panic 钩子"]
    #[tokio::test]
    async fn bridge_panic_chain_child() {
        if std::env::var_os(CHILD_MARKER).is_none() {
            return;
        }
        let (host, host_calls) = std::sync::mpsc::channel();
        std::panic::set_hook(Box::new(move |_| {
            let _ = host.send(());
        }));
        super::init_app();
        let directory = tests::TestDirectory::new();
        let service = directory.open(BridgeAppServiceSurface::Gui, 1, true).await;
        service.agree().await.unwrap();
        let result = flutter_rust_bridge::PanicBacktrace::catch_unwind(|| {
            suppress_panic_for_test(|| panic!("不得重复采集遥测自身的合成故障"));
        });
        assert!(result.err().unwrap().backtrace.is_some());
        host_calls.try_recv().unwrap();
        let line = line!() + 2;
        let result = flutter_rust_bridge::PanicBacktrace::catch_unwind(|| {
            panic!("不得进入遥测的合成消息");
        });
        assert!(result.err().unwrap().backtrace.is_some());
        host_calls.try_recv().unwrap();
        let payload = tests::panic_payload(&service);
        let payload = std::str::from_utf8(&payload).unwrap();
        assert!(payload.contains(r#""error_code":"panic""#));
        assert_eq!(payload.matches(r#""event":"crash""#).count(), 1);
        assert!(payload.contains(&format!(
            "crates/ubaa_flutter_bridge/src/api/simple.rs:{line}"
        )));
        assert!(!payload.contains("不得进入遥测的合成消息"));
        assert!(!payload.contains("backtrace"));
        assert!(host_calls.try_recv().is_err());
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
        tracing::warn!(
            target: "ubaa::app_service::school_gate",
            "无法读取应用服务门控状态，本次学校请求继续"
        );
        tracing::warn!(
            target: "ubaa::app_service::school_gate",
            detail = "gate-detail-secret",
            "带额外字段的门控事件"
        );
        tracing::debug!(
            target: "ubaa::app_service::school_gate",
            "gate-wrong-level"
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
