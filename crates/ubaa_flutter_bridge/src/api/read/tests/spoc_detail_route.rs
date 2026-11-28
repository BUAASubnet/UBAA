//! 列表来源与详情执行路线相互独立。
use super::{Fixture, SPOC_OLD, Transport, offline, restored};
use std::{sync::Arc, sync::atomic::Ordering::SeqCst};
use tokio::sync::Notify;
use ubaa_core::facade::{CachePublication, ConnectionMode, HomeQuery, HomeReadData};

#[tokio::test]
async fn spoc详情整次刷新采用webvpn离线列表后仍走direct并写回() {
    Box::pin(spoc_detail_reuses_competing_list(
        "webvpn",
        ConnectionMode::WebVpn,
    ))
    .await;
}

#[tokio::test]
async fn spoc详情整次刷新采用同路线离线列表仍正常完成() {
    Box::pin(spoc_detail_reuses_competing_list(
        "direct",
        ConnectionMode::Direct,
    ))
    .await;
}

async fn spoc_detail_reuses_competing_list(list_policy: &str, list_source: ConnectionMode) {
    let direct = Fixture::in_task("spoc_detail_route");
    let list = Fixture::in_task("spoc_detail_route");
    let pause = Arc::new((Notify::new(), Notify::new()));
    let slow = Transport {
        spoc_courses_pause: Some(Arc::clone(&pause)),
        ..Transport::default()
    };
    let detail_client = Arc::new(restored(direct.1.clone(), "direct", &slow).await);
    let list_client = restored(list.1.clone(), list_policy, &Transport::default()).await;
    let cache = offline(&direct.0).await;
    let competing_cache = offline(&direct.0).await;
    let read = tokio::spawn({
        let detail_client = Arc::clone(&detail_client);
        async move {
            detail_client
                .refresh_home_record(
                    &cache,
                    HomeQuery::SpocDetail {
                        assignment_id: "a1".into(),
                    },
                )
                .await
        }
    });
    tokio::time::timeout(crate::TEST_HANG_TIMEOUT, pause.0.notified())
        .await
        .unwrap();
    assert_eq!(slow.calls.spoc_terms.load(SeqCst), 1);
    assert!(!direct.cache().exists(), "整次刷新完成前不写回业务会话");
    let list = list_client
        .home_spoc_cached(&competing_cache)
        .await
        .unwrap();
    assert!(list.state.complete && list.state.saved_for_offline);
    assert_eq!(list.result.route.resolved_route, list_source.into());
    pause.1.notify_one();
    let result = read.await.unwrap().unwrap_or_else(|error| {
        panic!(
            "采用 {list_policy} 列表后应继续读取详情，实际错误：{:?}",
            error.code
        )
    });
    let HomeReadData::SpocDetail {
        data,
        offline_list_source_route,
    } = result.result.data
    else {
        panic!("首页详情刷新应返回 SPOC 详情");
    };
    let direct_route = ConnectionMode::Direct;
    assert_eq!(offline_list_source_route, Some(list_source));
    assert_eq!(result.result.resolution.mode, direct_route);
    assert_eq!(result.result.resolution.diagnostic.mode, direct_route);
    assert_eq!(result.result.scope.route, direct_route);
    assert_eq!(result.result.online_route, Some(direct_route));
    assert_eq!(result.online_routes, [direct_route]);
    assert_eq!(data.content_plain_text.as_deref(), Some("合成正文"));
    assert!(result.complete);
    assert_eq!(result.publication, Some(CachePublication::Stored));
    assert_eq!(slow.calls.spoc_pages.load(SeqCst), 0, "应复用已发布列表");
    assert_eq!(
        slow.calls.spoc_details[0].load(SeqCst),
        1,
        "详情正文必须凭 Direct 的 Token 和 RoleCode 通过夹具校验"
    );
    assert_eq!(slow.calls.spoc_details[1].load(SeqCst), 0);
    drop(detail_client);
    let document: serde_json::Value = serde_json::from_str(&direct.contents()).unwrap();
    assert_eq!(
        document["routes"]["direct"]["spoc"]["material"]["spoc"]["token"],
        SPOC_OLD
    );
    assert!(document["routes"]["webvpn"]["spoc"].is_null());
}
