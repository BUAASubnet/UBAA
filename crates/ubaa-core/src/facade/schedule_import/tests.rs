use super::*;
use crate::config::FeatureRouteConfig;
use crate::connection::{GatewayProbe, NetworkState, resolve_route};
use crate::domain::{ConnectionMode, RoutePolicy};
use crate::facade::{CacheKey, CacheLimits};
struct NoProbe;
impl GatewayProbe for NoProbe {
    fn probe(&self, _: std::time::Duration) -> NetworkState {
        panic!("固定路线不探测");
    }
}
#[test]
fn 会话清理和路线往返不能复活旧计划_计划不延长运行时寿命() {
    for clear_session in [false, true] {
        let root = std::env::temp_dir().join(format!(
            "ubaa-import-guard-{}-{clear_session}",
            std::process::id()
        ));
        let mut client = UbaaClient::open(&root).unwrap();
        client
            .set_default_route_policy(RoutePolicy::Direct)
            .unwrap();
        let cache = OfflineCache::open(
            &root,
            "0123456789abcdef0123456789abcdef",
            "synthetic",
            CacheKey::new([9; 32]),
            CacheLimits::default(),
        )
        .unwrap();
        let ticket = cache
            .begin(CacheScope {
                route: ConnectionMode::Direct,
                query: CacheQuery::ImportedSchedules,
            })
            .unwrap();
        let owner = client.direct_runtime.feature_state();
        let plan = ScheduleImport {
            resolution: resolve_route(
                RoutePolicy::Direct,
                FeatureRouteConfig::SAFE_DEFAULT,
                &NoProbe,
            ),
            owner: Arc::downgrade(&owner),
            generation: owner.lifecycle_generation(),
            route_generation: client.route_generation,
            cache: cache.clone(),
            ticket,
            term: "synthetic".into(),
            terms: Vec::new(),
            weeks: Vec::new(),
            schedules: BTreeMap::new(),
            terms_observation: None,
            weeks_observation: None,
            observations: BTreeMap::new(),
            stage: Stage::Terms,
            finished: false,
            cancellation: ScheduleImportCancellation(Arc::new(AtomicBool::new(false))),
        };
        drop(owner);
        client.validate_schedule_import(&plan).unwrap();
        if clear_session {
            client.direct_runtime.clear_feature_state();
        } else {
            client
                .set_default_route_policy(RoutePolicy::WebVpn)
                .unwrap();
            client
                .set_default_route_policy(RoutePolicy::Direct)
                .unwrap();
        }
        assert!(matches!(
            client.validate_schedule_import(&plan),
            Err(OfflineReadError::Cache(CacheError::Superseded))
        ));
        drop(client);
        assert!(plan.owner.upgrade().is_none());
        drop((plan, cache));
        std::fs::remove_dir_all(root).unwrap();
    }
}
