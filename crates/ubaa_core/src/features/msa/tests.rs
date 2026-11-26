use super::*;
use crate::domain::spoc_classroom::ClassroomStatus;
use serde_json::json;

#[test]
fn 课堂目录区分结构错误并且只保留安全的未知状态() {
    let mut data = json!({
        "id":"1", "title":"夹具课", "teachers":[], "term_name":"夹具学期",
        "sub_list":{"2026":{"11":{"26":[{
            "id":"2","sub_title":"夹具节次","class_begin":1,"class_over":2,
            "room_name":"夹具教室","lecturer_name":"夹具教师",
            "sub_status":"6","playback_status":-12
        }]}}}
    });
    let status = parse::catalog(&data, "1")
        .unwrap()
        .sessions
        .remove(0)
        .status;
    assert_eq!(
        status,
        ClassroomStatus::Other {
            sub_status: "6".into(),
            playback_status: "-12".into()
        }
    );
    data["sub_list"]["2026"]["11"]["26"][0]["sub_status"] = json!("fixture-private");
    for (value, safe) in [
        (json!("R9Ab1234"), "R9Ab1234"),
        (json!("a-b"), "invalid"),
        (json!("012345678"), "invalid"),
        (json!("中文"), "invalid"),
        (json!(""), "invalid"),
        (json!(null), "invalid"),
        (json!({}), "invalid"),
    ] {
        data["sub_list"]["2026"]["11"]["26"][0]["playback_status"] = value;
        let status = parse::catalog(&data, "1")
            .unwrap()
            .sessions
            .remove(0)
            .status;
        assert_eq!(
            status,
            ClassroomStatus::Other {
                sub_status: "invalid".into(),
                playback_status: safe.into()
            }
        );
    }
    data["sub_list"] = json!([]);
    let error = parse::catalog(&data, "1").unwrap_err();
    assert_eq!(error.diagnostic().reason.as_deref(), Some("sub_list_shape"));
}

fn recording(link: &str, mode: ConnectionMode) -> Result<ClassroomSession> {
    parse::session(
        &json!({"sub_status":"6","sub_title":"课","start_at":1,"end_at":2,"video_list":{},"playurl":{"0":link}}),
        mode,
    )
}

fn slides(image: &str, thumb: &str, mode: ConnectionMode) -> Result<SlideTimeline> {
    parse::slides(
        &json!({"list":[{"content":json!({"pptimgurl":image,"pptthumb":thumb}).to_string()}]}),
        mode,
    )
}

#[test]
fn 课堂媒体和幻灯片拒绝不安全地址并返回规范地址() {
    let valid = format!("https://{RESOURCE}/12.jpg");
    let canonical = format!("HTTPS://{}:443/a/../12.jpg", RESOURCE.to_uppercase());
    let wrapped = crate::connection::to_webvpn_url(&valid).unwrap();
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let mut rejected = vec![
            format!("https://{RESOURCE}\\/12.jpg"),
            format!("https://user@{RESOURCE}/12.jpg"),
            format!("https://@{RESOURCE}/12.jpg"),
            format!("https://{RESOURCE}:8443/12.jpg"),
            format!("\t{valid}"),
            format!("{valid}\u{7f}"),
            format!("{valid}?x=\u{2003}"),
            wrapped.replace("/https/", "/http/"),
            wrapped.replace("/12.jpg", "\\/12.jpg"),
        ];
        if mode == ConnectionMode::Direct {
            rejected.push(wrapped.clone());
        }
        for link in rejected {
            assert!(recording(&link, mode).is_err(), "{link:?}");
            assert!(slides(&link, &valid, mode).is_err());
            assert!(slides(&valid, &link, mode).is_err());
        }
        let mut accepted = vec![canonical.clone()];
        if mode == ConnectionMode::WebVpn {
            accepted.push(wrapped.replace("/https/", "/https-443/"));
        }
        for link in accepted {
            assert_eq!(recording(&link, mode).unwrap().sources[0].url, valid);
            assert_eq!(
                slides(&link, &link, mode).unwrap().slides[0].thumb_url,
                valid
            );
        }
    }
}

#[test]
fn 课堂媒体领域类型的调试输出不含地址() {
    let media = format!("https://{RESOURCE}/12.jpg?auth_key=fixture-media");
    let timeline = slides(&media, &media, ConnectionMode::Direct).unwrap();
    let session = recording(&media, ConnectionMode::Direct).unwrap();
    for debug in [
        format!("{session:?}"),
        format!("{:?}", session.sources[0]),
        format!("{timeline:#?}"),
        format!("{:?}", timeline.slides[0]),
    ] {
        assert!(!debug.contains(RESOURCE) && !debug.contains("fixture-media"));
    }
}

#[tokio::test]
async fn 课堂登录期间撤销代次后不保存或发送新令牌() {
    use crate::{
        ports::HttpTransport,
        session::{FileSessionStore, SessionSnapshot, SessionStore},
    };
    use std::sync::Arc;
    use tokio::sync::Notify;
    struct Pending(Arc<Notify>, Arc<Notify>);
    #[async_trait::async_trait]
    impl HttpTransport for Pending {
        async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
            assert!(request.url.contains("/casapi/index.php"));
            self.0.notify_one();
            self.1.notified().await;
            let mut response = HttpResponse::new(302, request.url, vec![]);
            response
                .headers
                .insert("Location".into(), vec![format!("https://{CLASS}/")]);
            response.headers.insert("Set-Cookie".into(),vec!["_token=%7Bi%3A0%3Bs%3A6%3A%22_token%22%3Bi%3A1%3Bs%3A8%3A%22TEST_JWT%22%3B%7D; Path=/; Secure".into()]);
            Ok(response)
        }
    }
    let root = crate::test_tmp::test_temp_dir("msa_revocation").unwrap();
    let store = FileSessionStore::new(&root).unwrap();
    store
        .compare_exchange(
            store.load_versioned().unwrap().revision,
            Some(&SessionSnapshot {
                mode: ConnectionMode::Direct,
                cookies: vec![],
                authenticated_at: 1,
                last_activity: 1,
            }),
        )
        .unwrap();
    let started = Arc::new(Notify::new());
    let finish = Arc::new(Notify::new());
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        Pending(started.clone(), finish.clone()),
        store,
    )
    .unwrap();
    let mut sibling = runtime.fork_with_cookie_filter(|_| true);
    sibling.reset_msa();
    let (result, ()) = tokio::join!(auth::credential(&mut runtime, None), async {
        started.notified().await;
        sibling.renew_authentication_generation();
        finish.notify_one();
    });
    let error = result.unwrap_err();
    let revoked = auth::credential(&mut runtime, None).await.unwrap_err();
    assert_eq!(error.code, revoked.code);
    assert!(runtime.msa.credential().is_none());
}
