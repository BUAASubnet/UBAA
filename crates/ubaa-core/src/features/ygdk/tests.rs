use async_trait::async_trait;

use crate::domain::{ConnectionMode, YgdkClockinSubmitRequest, YgdkPhotoUpload};
use crate::ports::{HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::FileSessionStore;

use super::YgdkCredential;
use super::auth::{code_from_url, percent_decode};
use super::parser::parse_records;
use super::upload::build_upload_body;
use super::write::submit_clockin;

#[test]
fn 从回调片段查询中提取授权码() {
    assert_eq!(
        code_from_url("https://ygdk.buaa.edu.cn/#/home?code=%E5%B7%B2%E8%84%B1%E6%95%8F"),
        Some("已脱敏".into())
    );
}

#[test]
fn 解码不含等号的业务令牌值() {
    assert_eq!(percent_decode("token%2Bvalue%2Ftail"), "token+value/tail");
}

#[test]
fn 阳光打卡凭据调试输出不泄露令牌() {
    let credential = YgdkCredential {
        uid: 42,
        token: "ygdk-secret-token".into(),
    };
    let rendered = format!("{credential:?}");
    assert!(!rendered.contains("ygdk-secret-token"));
}

#[test]
fn 记录时间戳按冻结东八区格式化() {
    let body = serde_json::json!({
        "code": 1,
        "result": {"list": [{"record_id": 1, "start_time": 1_772_323_200, "end_time": 1_772_326_800}]}
    })
    .to_string();
    let page = parse_records(&body, &[], 1, 10).expect("解析记录");
    assert_eq!(
        page.content[0].start_time.as_deref(),
        Some("2026-03-01 08:00")
    );
}

#[test]
fn 数字字符串时间戳同样按冻结格式化() {
    let body = serde_json::json!({
        "code": 1,
        "result": {"list": [{"record_id": 1, "start_time": "1772323200"}]}
    })
    .to_string();
    let page = parse_records(&body, &[], 1, 10).expect("解析记录");
    assert_eq!(
        page.content[0].start_time.as_deref(),
        Some("2026-03-01 08:00")
    );
}

#[test]
fn 记录图片格式化字符串按单个地址保留() {
    let body = serde_json::json!({
        "code": 1,
        "result": {"list": [{"record_id": 1, "images_fmt": "https://img/one"}]}
    })
    .to_string();
    let page = parse_records(&body, &[], 1, 10).expect("解析记录");
    assert_eq!(page.content[0].images, vec!["https://img/one"]);
}

#[test]
fn 记录文本原语按冻结实现转为字符串() {
    let body = serde_json::json!({
        "code": 1,
        "result": {"list": [{"record_id": 1, "item_name": 7, "place": true}]}
    })
    .to_string();
    let page = parse_records(&body, &[], 1, 10).expect("解析记录");
    assert_eq!(page.content[0].item_name.as_deref(), Some("7"));
    assert_eq!(page.content[0].place.as_deref(), Some("true"));
}

#[test]
fn 阳光打卡上传正文匹配冻结_multipart_字段() {
    let credential = YgdkCredential {
        uid: 7,
        token: "tok".into(),
    };
    let photo = YgdkPhotoUpload {
        file_name: "p.jpg".into(),
        mime_type: "image/jpeg".into(),
        bytes: b"PNG".to_vec(),
    };
    let body = String::from_utf8(build_upload_body(&credential, &photo, "b")).unwrap();
    assert!(body.contains("name=\"uid\"\r\n\r\n7"));
    assert!(body.contains("name=\"token\"\r\n\r\ntok"));
    assert!(body.contains("name=\"file\"; filename=\"p.jpg\""));
    assert!(body.ends_with("\r\n--b--\r\n"));
}

#[test]
fn 无效打卡输入在任何网络请求前被拒绝() {
    let mut runtime = ClientRuntime::new(
        ConnectionMode::Direct,
        NoNetworkTransport,
        FileSessionStore::new(
            std::env::temp_dir().join(format!("ubaa-ygdk-input-{}", std::process::id())),
        )
        .unwrap(),
    )
    .unwrap();
    let result = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
        .block_on(submit_clockin(
            &mut runtime,
            YgdkClockinSubmitRequest::default(),
        ))
        .unwrap_err();
    assert_eq!(result.code, crate::error::ErrorCode::InvalidInput);
    assert_eq!(result.message, "打卡照片不能为空");
}

struct NoNetworkTransport;

#[async_trait]
impl HttpTransport for NoNetworkTransport {
    async fn execute(&self, _request: HttpRequest) -> crate::error::Result<HttpResponse> {
        panic!("无效输入不应触发网络请求");
    }
}

mod contract {
    use super::super::parser::{parse_items, parse_overview, parse_records};

    #[test]
    fn 解析阳光打卡概览并选择跑步项目() {
        let classify = r#"{"code":1,"result":{"list":[{"classify_id":1,"name":"阳光体育","term_num":10,"week_num":2}]}}"#;
        let items =
            r#"{"code":1,"result":{"list":[{"item_id":2,"name":"跑步","type":1,"sort":1}]}}"#;
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
}
