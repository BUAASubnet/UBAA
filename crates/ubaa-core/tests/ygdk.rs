use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use ubaa_core::domain::{ConnectionMode, YgdkClockinSubmitRequest, YgdkPhotoUpload};
use ubaa_core::facade::RouteClient;
use ubaa_core::features::ygdk::{parse_items, parse_overview, parse_records};
use ubaa_core::ports::{HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::session::{FileSessionStore, SessionSnapshot, SessionStore};

#[test]
fn 解析阳光打卡概览并选择跑步项目() {
    let classify = r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育","term_num":10,"week_num":2}]}}"#;
    let items = r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步","type":1,"sort":1}]}}"#;
    let count = r#"{"code":1,"result":{"term_good_count_show":3,"week_count":1,"month_count":2,"day_count":1}}"#;
    let term = r#"{"code":1,"result":{"term_id":9,"name":"2025秋"}}"#;
    let overview = parse_overview(classify, items, count, term).unwrap();
    assert_eq!(overview.default_item_id, 2);
    assert_eq!(overview.summary.term_count, 3);
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

#[test]
fn 概览统计和学期请求失败仍按冻结实现返回基础数据() {
    let root = std::env::temp_dir().join(format!("ubaa-ygdk-optional-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let mut client =
        RouteClient::with_transport(ConnectionMode::Direct, YgdkOptionalTransport, store).unwrap();
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let overview = runtime.block_on(client.ygdk_overview()).unwrap().data;
    assert_eq!(overview.default_item_name, "跑步");
    assert_eq!(overview.summary.term_count, 0);
    assert!(overview.summary.term_id.is_none());
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn 阳光打卡写链按冻结顺序完成登录概览上传和提交() {
    let root = std::env::temp_dir().join(format!("ubaa-ygdk-write-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    let requests = Arc::new(Mutex::new(Vec::new()));
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        YgdkWriteTransport {
            requests: Arc::clone(&requests),
        },
        store,
    )
    .unwrap();
    let request = YgdkClockinSubmitRequest {
        item_id: Some(2),
        start_time: Some("08:00".into()),
        end_time: Some("09:00".into()),
        place: Some("操场".into()),
        share_to_square: Some(false),
        photo: Some(YgdkPhotoUpload {
            file_name: "p.jpg".into(),
            mime_type: "image/jpeg".into(),
            bytes: b"JPEG".to_vec(),
        }),
    };
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    let result = runtime.block_on(client.ygdk_submit(request)).unwrap().data;
    assert!(result.success);

    let requests = requests.lock().unwrap();
    let paths: Vec<_> = requests
        .iter()
        .map(|request| url::Url::parse(&request.url).unwrap().path().to_owned())
        .collect();
    assert_eq!(
        paths,
        vec![
            "/uc/api/oauth/index",
            "/api/Front/Clockin/User/campusAppLogin",
            "/api/Front/Clockin/Classify/getList",
            "/api/Front/Clockin/Item/getList",
            "/api/Front/Clockin/Clockin/getCount",
            "/api/Front/Clockin/Term/get",
            "/api/Front/Upload/File/post",
            "/api/Front/Clockin/Clockin/clockin",
        ]
    );
    let upload = &requests[6];
    let upload_body = String::from_utf8_lossy(&upload.body);
    assert!(upload_body.contains("name=\"uid\"\r\n\r\n7"));
    assert!(upload_body.contains("name=\"token\"\r\n\r\ntok"));
    assert!(upload_body.contains("name=\"file\"; filename=\"p.jpg\""));
    let submit = String::from_utf8_lossy(&requests[7].body);
    assert!(submit.contains("start_time=08%3A00"));
    assert!(submit.contains("item_id=2"));
    assert!(submit.contains("images=%5B%22uploaded.jpg%22%5D"));
    let _ = std::fs::remove_dir_all(root);
}

#[derive(Clone)]
struct YgdkWriteTransport {
    requests: Arc<Mutex<Vec<HttpRequest>>>,
}

struct YgdkOptionalTransport;

#[async_trait]
impl HttpTransport for YgdkOptionalTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        let url = url::Url::parse(&request.url).map_err(|_| test_error("invalid test URL"))?;
        let path = url.path();
        let body = match path {
            "/uc/api/oauth/index" => Vec::new(),
            "/api/Front/Clockin/User/campusAppLogin" => {
                br#"{"code":1,"result":{"uid":7,"token":"tok"}}"#.to_vec()
            }
            "/api/Front/Clockin/Classify/getList" => {
                r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"}]}}"#
                    .as_bytes()
                    .to_vec()
            }
            "/api/Front/Clockin/Item/getList" => {
                r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步","sort":1}]}}"#
                    .as_bytes()
                    .to_vec()
            }
            "/api/Front/Clockin/Clockin/getCount" | "/api/Front/Clockin/Term/get" => {
                return Err(test_error("optional ygdk request failed"));
            }
            _ => return Err(test_error("unexpected ygdk path")),
        };
        let final_url = if path == "/uc/api/oauth/index" {
            "https://app.buaa.edu.cn/uc/api/oauth/index?code=code-safe".into()
        } else {
            request.url
        };
        Ok(HttpResponse::new(200, final_url, body))
    }
}

#[async_trait]
impl HttpTransport for YgdkWriteTransport {
    async fn execute(&self, request: HttpRequest) -> ubaa_core::error::Result<HttpResponse> {
        let url = url::Url::parse(&request.url).map_err(|_| test_error("invalid test URL"))?;
        let path = url.path();
        self.requests.lock().unwrap().push(request.clone());
        let body = match path {
            "/uc/api/oauth/index" => Vec::new(),
            "/api/Front/Clockin/User/campusAppLogin" =>
                br#"{"code":1,"result":{"uid":7,"token":"tok"}}"#.to_vec(),
            "/api/Front/Clockin/Classify/getList" =>
                r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育"} ]}}"#.as_bytes().to_vec(),
            "/api/Front/Clockin/Item/getList" =>
                r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步"}]}}"#.as_bytes().to_vec(),
            "/api/Front/Clockin/Clockin/getCount" =>
                br#"{"code":1,"result":{"term_good_count_show":1,"week_count":1,"month_count":1,"day_count":1}}"#.to_vec(),
            "/api/Front/Clockin/Term/get" =>
                r#"{"code":1,"result":{"term_id":9,"name":"2025秋"}}"#.as_bytes().to_vec(),
            "/api/Front/Upload/File/post" =>
                br#"{"code":1,"result":{"file_name":"uploaded.jpg"}}"#.to_vec(),
            "/api/Front/Clockin/Clockin/clockin" =>
                br#"{"code":1,"result":{"record_id":8}}"#.to_vec(),
            _ => return Err(test_error("unexpected ygdk path")),
        };
        let final_url = if path == "/uc/api/oauth/index" {
            "https://app.buaa.edu.cn/uc/api/oauth/index?code=code-safe".into()
        } else {
            request.url
        };
        Ok(HttpResponse::new(200, final_url, body))
    }
}

fn test_error(message: &'static str) -> ubaa_core::error::UbaaError {
    ubaa_core::error::UbaaError::new(
        ubaa_core::error::ErrorCode::InternalError,
        ubaa_core::error::ErrorKind::Internal,
        false,
        message,
    )
}
