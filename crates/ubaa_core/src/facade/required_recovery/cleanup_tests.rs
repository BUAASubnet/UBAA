//! 并行只读组的条件清理必须保留后来捕获的新代次和另一条路线。
use super::*;
use std::sync::Barrier;

#[test]
fn 旧组比较后迟到清理不能再次推进代次或误伤新组另一条路线() {
    let mut fixture = Fixture::new(0, true, None);
    fixture.client.config = RouteConfig::parse(
        "[route]\ndefault = \"webvpn\"\n[route.features]\nschedule = \"direct\"\n",
    )
    .unwrap();
    let mut first = fixture.client.fork_parallel_readonly().unwrap();
    let mut second = fixture.client.fork_parallel_readonly().unwrap();
    let direct = fixture.client.direct_runtime.feature_state();
    let webvpn = fixture.client.webvpn_runtime.feature_state();
    let initial = direct.lifecycle_generation();
    let webvpn_generation = webvpn.lifecycle_generation();
    webvpn.cgyy.set("synthetic-webvpn-token".into());

    // A 已观察到父代次匹配，暂停在最终清理之前。只暂停 A 的第一次清理。
    let observed = Arc::new(Barrier::new(2));
    let resume = Arc::new(Barrier::new(2));
    let once = AtomicBool::new(false);
    first.direct_runtime.set_readonly_invalidate_hook(Arc::new({
        let observed = observed.clone();
        let resume = resume.clone();
        move || {
            if !once.swap(true, Ordering::SeqCst) {
                observed.wait();
                resume.wait();
            }
        }
    }));
    fixture
        .transport
        .response_status
        .store(401, Ordering::SeqCst);
    let executor = || {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
    };
    let first_read = std::thread::spawn(move || {
        executor().block_on(first.recover_required_session(ReadonlyFeature::Schedule))
    });
    observed.wait();
    let second_error = executor()
        .block_on(second.recover_required_session(ReadonlyFeature::Schedule))
        .unwrap_err();
    assert_eq!(second_error.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(
        second_error.resolution.unwrap().mode,
        ConnectionMode::Direct
    );
    assert_eq!(direct.lifecycle_generation(), initial + 1);
    assert_eq!(fixture.transport.requests.lock().unwrap().len(), 4);

    // B 已完成清理。C 经公开 fork 捕获 (G+1, W)，尚未调用任何路线解析。
    let mut current = fixture.client.fork_parallel_readonly().unwrap();
    let current_webvpn_identity = current.webvpn_runtime.authentication_generation();
    assert!(current.direct_runtime.ensure_session_revision().is_ok());
    assert!(current.webvpn_runtime.ensure_session_revision().is_ok());
    resume.wait();
    let first_error = first_read.join().unwrap().unwrap_err();
    assert_eq!(first_error.error.code, ErrorCode::AuthenticationRequired);
    assert_eq!(first_error.resolution.unwrap().mode, ConnectionMode::Direct);
    fixture
        .transport
        .response_status
        .store(200, Ordering::SeqCst);
    let result = executor().block_on(current.recover_required_session(ReadonlyFeature::Network));

    // 一并报告所有外部效果，红测可同时显示未发送读取、重复推进及 WebVPN 误清。
    let actual = (
        result.as_ref().map(|r| r.resolution.mode).ok(),
        fixture.transport.requests.lock().unwrap().len(),
        direct.lifecycle_generation(),
        webvpn.lifecycle_generation(),
        fixture.client.webvpn_runtime.authentication_revoked(),
        current.webvpn_runtime.authentication_generation() == current_webvpn_identity,
        current.webvpn_runtime.ensure_session_revision().is_ok(),
        webvpn.cgyy.token(),
    );
    assert_eq!(
        actual,
        (
            Some(ConnectionMode::WebVpn),
            6,
            initial + 1,
            webvpn_generation,
            false,
            true,
            true,
            Some("synthetic-webvpn-token".into()),
        ),
        "新组 WebVPN 读取必须成功，且旧组不能重复推进 Direct 或撤销 WebVPN：{result:?}",
    );
}
