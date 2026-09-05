use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};

use ubaa_core::facade::testing::{FileSessionStore, RouteConfig};
use ubaa_core::facade::{ConnectionMode, UbaaClient};

use super::evaluation_support::{EvaluationMock, Scenario, runtime};
use super::{CountingTransport, NeverProbe, save_both_routes, test_root};

#[test]
fn caller_pinned_readback_uses_only_the_requested_route_and_never_sends_final() {
    let root = test_root("caller-pinned");
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    save_both_routes(&store);
    let direct = EvaluationMock::new(Scenario::one_course());
    let webvpn_calls = Arc::new(AtomicUsize::new(0));
    let mut client = UbaaClient::with_routing(
        direct.clone(),
        CountingTransport(Arc::clone(&webvpn_calls)),
        store,
        RouteConfig::parse("[route]\ndefault = \"auto\"\n").unwrap(),
        NeverProbe,
    )
    .unwrap();

    let response = runtime()
        .block_on(client.evaluation_all_on_route(ConnectionMode::Direct))
        .unwrap();

    assert_eq!(response.pinned_route, ConnectionMode::Direct);
    assert_eq!(response.data.courses.len(), 1);
    assert_eq!(webvpn_calls.load(Ordering::SeqCst), 0);
    let requests = direct.requests();
    assert_eq!(requests.len(), 4);
    assert!(requests.iter().all(|request| {
        let path = url::Url::parse(&request.url).unwrap().path().to_owned();
        !path.ends_with("reviseQuestionnairePattern")
            && !path.ends_with("getQuestionnaireTopic")
            && !path.ends_with("submitSaveEvaluation")
    }));
    let _ = std::fs::remove_dir_all(root);
}
