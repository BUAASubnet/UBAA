use super::*;
use crate::{
    domain::{ConnectionMode, DualLoginInput, SecretValue},
    error::{ErrorCode, Result},
    facade::{
        AgendaContent, AgendaItem, AgendaKind, AgendaQuery, AgendaStore, AgendaTime,
        CacheCompleteness, CacheKey, CacheLimits, CachePayload, CacheQuery, CacheScope,
        OfflineCache, OfflineRepository, testing::RouteConfig,
    },
    ports::{HttpFileRange, HttpRequest, HttpResponse, HttpTransferObserver, HttpTransport},
    session::FileSessionStore,
};
use std::{
    sync::atomic::{AtomicUsize, Ordering},
    time::Duration,
};

#[derive(Clone, Default)]
struct School(Arc<AtomicUsize>);

#[async_trait::async_trait]
impl HttpTransport for School {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.0.fetch_add(1, Ordering::SeqCst);
        Ok(HttpResponse::new(503, request.url, Vec::new()))
    }

    async fn upload(
        &self,
        request: HttpRequest,
        _: Option<HttpFileRange>,
        _: Arc<dyn HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        self.execute(request).await
    }

    async fn download(
        &self,
        request: HttpRequest,
        _: std::fs::File,
        _: Arc<dyn HttpTransferObserver>,
    ) -> Result<HttpResponse> {
        self.execute(request).await
    }
}

struct Bootstrap;

#[async_trait::async_trait]
impl HttpTransport for Bootstrap {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let body = serde_json::json!({
            "schema": 1,
            "update": {
                "status": "update_required",
                "latest_version": "3.0.0+1",
                "min_supported_version": "3.0.0",
                "url": "https://update.example.test/release",
                "release_notes": null
            },
            "announcements": []
        });
        Ok(HttpResponse::new(
            200,
            request.url,
            body.to_string().into_bytes(),
        ))
    }
}

struct Probe;
impl crate::connection::GatewayProbe for Probe {
    fn probe(&self, _: Duration) -> crate::connection::NetworkState {
        panic!("门控已生效，不应探测学校网络");
    }
}

#[tokio::test]
async fn 门控拒绝学校发送与路由探测并保留本机缓存日程和导出() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../.ubaa_local/app_service/test_gate")
        .join(uuid::Uuid::new_v4().to_string());
    {
        let school = School::default();
        let mut client = UbaaClient::with_routing(
            school.clone(),
            school.clone(),
            FileSessionStore::new(&root).unwrap(),
            RouteConfig::default(),
            Probe,
        )
        .unwrap();
        let config = AppServiceConfig::from_build(
            Some("http://127.0.0.1:8787"),
            Some("github"),
            Some("2.1.0+1"),
            Platform::Macos,
            false,
        );
        let gui = open_installation(&root, config.clone(), Surface::Gui, 1).unwrap();
        let command = open_installation(&root, config, Surface::Command, 1).unwrap();
        gui.agree(1).unwrap();
        gui.refresh_bootstrap_with(&Bootstrap, true).await.unwrap();
        client.bind_app_service(Arc::new(command));

        let expected = |error: crate::error::UbaaError| {
            assert_eq!(error.code, ErrorCode::UpdateRequired);
            assert!(!error.retryable);
        };
        expected(
            client
                .login(DualLoginInput {
                    username: "synthetic-user".into(),
                    password: SecretValue::new("synthetic-secret"),
                })
                .await
                .unwrap_err(),
        );
        expected(client.recover_connection_session().await.unwrap_err().error);
        let Err(crate::facade::AgendaSyncError::Remote(error)) = client.agenda_sync_scope() else {
            panic!("门控应先于日程同步的 Auto 路线缓存检查");
        };
        expected(error);

        expected(client.grades("2026-1").await.unwrap_err().error);
        expected(
            client
                .fork_parallel_readonly()
                .unwrap()
                .grades("2026-1")
                .await
                .unwrap_err()
                .error,
        );
        let url = "https://school.example.test/request";
        assert_runtime_gate(&mut client, &school, url, &root).await;
        assert_local_features(&root);
        assert_eq!(school.0.load(Ordering::SeqCst), 0);

        gui.enter_basic().unwrap();
        assert_eq!(
            client
                .direct_runtime
                .request(HttpRequest::get(url))
                .await
                .unwrap()
                .status,
            503
        );
        assert_eq!(school.0.load(Ordering::SeqCst), 1);
    }
    std::fs::remove_dir_all(root).unwrap();
}

async fn assert_runtime_gate(client: &mut UbaaClient, school: &School, url: &str, root: &Path) {
    let expected = |error: crate::error::UbaaError| {
        assert_eq!(error.code, ErrorCode::UpdateRequired);
        assert!(!error.retryable);
    };
    let observed = client.observe_write_boundary();
    let runtime = &mut client.direct_runtime;
    expected(runtime.request(HttpRequest::get(url)).await.unwrap_err());
    expected(
        runtime
            .request_non_idempotent(HttpRequest::post(url, vec![]))
            .await
            .unwrap_err(),
    );
    expected(
        runtime
            .request_bearer_only(HttpRequest::post(url, vec![]), true)
            .await
            .unwrap_err(),
    );
    let transfer = crate::facade::bhpan::BhpanTransfer::new();
    expected(
        runtime
            .object_upload(HttpRequest::post(url, vec![]), None, &transfer, || Ok(()))
            .await
            .unwrap_err(),
    );
    expected(
        runtime
            .object_download(
                HttpRequest::get(url),
                std::fs::File::create(root.join("download")).unwrap(),
                &transfer,
            )
            .await
            .unwrap_err(),
    );
    assert!(!observed.may_have_been_sent());
    assert_eq!(school.0.load(Ordering::SeqCst), 0);
}

fn assert_local_features(root: &Path) {
    let alias = uuid::Uuid::new_v4().simple().to_string();
    let key = || CacheKey::new([7; 32]);
    let scope = CacheScope {
        route: ConnectionMode::Direct,
        query: CacheQuery::ScheduleToday {
            date: "2026-11-11".into(),
        },
    };
    let mut cache = OfflineRepository::open(root, &alias, key(), CacheLimits::default()).unwrap();
    let ticket = cache.begin_read(scope.clone()).unwrap();
    cache
        .publish(
            &ticket,
            CachePayload::Today(vec![]),
            1,
            CacheCompleteness::Complete,
        )
        .unwrap();
    drop(cache);
    let cache = OfflineCache::open(
        root,
        &alias,
        "synthetic-user",
        key(),
        CacheLimits::default(),
    )
    .unwrap();
    assert_eq!(
        cache.read(&scope, 2).unwrap().unwrap().payload,
        CachePayload::Today(vec![])
    );

    let agenda = AgendaStore::open(root, &alias).unwrap();
    let now = AgendaTime::new("2026-11-11T08:00:00+08:00".parse().unwrap());
    let title = "本机日程";
    agenda
        .create(AgendaItem::new(
            AgendaContent {
                kind: AgendaKind::Event,
                title: title.into(),
                location: None,
                notes: None,
                color: None,
                start: Some(now),
                end: Some(AgendaTime::new(
                    "2026-11-11T09:00:00+08:00".parse().unwrap(),
                )),
                all_day: false,
                due: None,
            },
            now,
        ))
        .unwrap();
    let query = AgendaQuery::new(
        ConnectionMode::Direct,
        String::new(),
        "2026-11-11".parse().unwrap(),
        "2026-11-12".parse().unwrap(),
        now,
    );
    assert_eq!(agenda.query_local_agenda(&query).unwrap().entries.len(), 1);
    let export = cache
        .export_agenda_ics(&agenda, &query, false)
        .unwrap()
        .snapshot;
    assert_eq!(export.exported_count, 1);
    assert!(export.ics.contains(title));
}
