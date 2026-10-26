use std::sync::Arc;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::time::Duration;

use async_trait::async_trait;
use ubaa_core::facade::testing::{
    DualSessionSnapshot, FileSessionStore, GatewayProbe, HttpRequest, HttpResponse, HttpTransport,
    RouteConfig, RouteSessionSnapshot,
};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, EvaluationSubmitCoursesRequest, EvaluationSubmitTarget,
    NetworkState, Result, UbaaClient,
};

#[path = "evaluation/authority.rs"]
mod authority;
#[path = "evaluation/batch.rs"]
mod batch;
#[path = "evaluation/support.rs"]
mod evaluation_support;
#[path = "evaluation/protocol.rs"]
mod protocol;
#[path = "evaluation/readback.rs"]
mod readback;
#[path = "evaluation/route_atomicity.rs"]
mod route_atomicity;

fn target(label: &str) -> EvaluationSubmitTarget {
    EvaluationSubmitTarget {
        rwid: format!("rw-{label}"),
        wjid: format!("wj-{label}"),
        kcdm: format!("kc-{label}"),
        bpdm: Some(format!("bp-{label}")),
    }
}

fn request(labels: &[&str]) -> EvaluationSubmitCoursesRequest {
    EvaluationSubmitCoursesRequest {
        targets: labels.iter().map(|label| target(label)).collect(),
    }
}

fn test_root(label: &str) -> std::path::PathBuf {
    static NEXT: AtomicU64 = AtomicU64::new(0);
    std::env::temp_dir().join(format!(
        "ubaa-evaluation-{label}-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ))
}

fn save_both_routes(store: &FileSessionStore) {
    store
        .save_dual(&DualSessionSnapshot::new(
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
            Some(RouteSessionSnapshot {
                cookies: Vec::new(),
                authenticated_at: 1_000,
                last_activity: 1_001,
            }),
        ))
        .unwrap();
}

#[derive(Clone)]
struct CountingTransport(Arc<AtomicUsize>);

#[async_trait]
impl HttpTransport for CountingTransport {
    async fn execute(&self, _request: HttpRequest) -> Result<HttpResponse> {
        self.0.fetch_add(1, Ordering::SeqCst);
        panic!("该测试不允许 HTTP")
    }
}

struct NeverProbe;

impl GatewayProbe for NeverProbe {
    fn probe(&self, _budget: Duration) -> NetworkState {
        panic!("显式路线不应执行网关探测")
    }
}
