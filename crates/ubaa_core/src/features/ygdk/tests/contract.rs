use crate::domain::{ActionEligibility, YgdkSubmitTarget};

use crate::features::ygdk::parser::{parse_items, parse_overview, parse_records};

#[test]
fn 解析阳光打卡概览并选择跑步项目() {
    let classify = r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育","term_num":10,"week_num":2}]}}"#;
    let items = r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步","type":1,"sort":1}]}}"#;
    let count = r#"{"code":1,"result":{"term_good_count_show":3,"week_count":1,"month_count":2,"day_count":1}}"#;
    let term = r#"{"code":1,"result":{"term_id":9,"name":"2025秋"}}"#;
    let overview = parse_overview(classify, items, count, term).unwrap();
    assert_eq!(overview.default_item_id, 2);
    assert_eq!(overview.summary.term_count, 3);
    assert_eq!(
        overview.items[0].submit_eligibility,
        ActionEligibility::Allowed
    );
    assert_eq!(
        overview.items[0].submit_target,
        Some(YgdkSubmitTarget {
            classify_id: 1,
            item_id: 2,
        })
    );
}

#[test]
fn 解析记录图片和分页状态并拒绝非法页码() {
    let items =
        parse_items(r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"}]}}"#).unwrap();
    let body = r#"{"code":1,"result":{"total":3,"list":[{"record_id":8,"item_id":2,"start_time":"2025-08-01 08:00","end_time":"2025-08-01 09:00","isopen":1,"images_fmt":["https://img/1"],"create_time_fmt":"2025-08-01 09:01"}]}}"#;
    let page = parse_records(body, &items, 1, 2).unwrap();
    assert!(page.has_more);
    assert_eq!(page.content[0].item_name.as_deref(), Some("跑步"));
    assert_eq!(page.content[0].images, vec!["https://img/1"]);
    assert!(parse_records(body, &items, 0, 2).is_err());
}

#[tokio::test]
async fn 记录页拒绝原样返回错误并清掉当前业务凭据() {
    use crate::domain::{ConnectionMode, YgdkOverview};
    use crate::error::{ErrorCode, Result};
    use crate::features::ygdk::YgdkCredential;
    use crate::features::ygdk::read::{YgdkOverviewContext, get_records_in_context};
    use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
    use crate::runtime::ClientRuntime;
    use crate::session::FileSessionStore;
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct RejectRecords(u16, Arc<AtomicUsize>);
    #[async_trait::async_trait]
    impl HttpTransport for RejectRecords {
        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
            assert!(request.url.contains("/Clockin/Clockin/getList?"));
            self.1.fetch_add(1, Ordering::SeqCst);
            Ok(HttpResponse::new(
                self.0,
                request.url,
                br#"{"code":-98}"#.to_vec(),
            ))
        }
    }

    for (status, message) in [(200, "阳光打卡业务会话已失效"), (401, "阳光打卡：需要认证")]
    {
        let path = crate::test_tmp::test_temp_dir("ubaa_core_features_ygdk_contract").unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let mut runtime = ClientRuntime::new(
            ConnectionMode::Direct,
            RejectRecords(status, Arc::clone(&calls)),
            FileSessionStore::new(&path).unwrap(),
        )
        .unwrap();
        let state = runtime.feature_state();
        let generation = state.ygdk.generation();
        let credential = YgdkCredential {
            uid: 7,
            token: "fixture-records".into(),
        };
        assert!(state.ygdk.store_credential(generation, credential.clone()));
        let context = YgdkOverviewContext {
            overview: YgdkOverview {
                classify_id: 3,
                ..YgdkOverview::default()
            },
            complete: true,
            generation,
            credential,
        };
        let error = get_records_in_context(&mut runtime, &context, 1, 10)
            .await
            .unwrap_err();
        assert_eq!(error.code, ErrorCode::AuthenticationRequired);
        assert_eq!(error.message, message);
        assert!(!error.retryable);
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert!(state.ygdk.credential().is_none());
        assert_ne!(state.ygdk.generation(), generation);
        std::fs::remove_dir_all(path).unwrap();
    }
}
