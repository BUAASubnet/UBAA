use super::{CURRENT_USER_URL, classify_undergraduate_portal};
use crate::connection::to_webvpn_url;
use crate::error::ErrorCode;
use crate::ports::HttpResponse;

#[test]
fn 门户200必须包含业务成功和有效用户不能以html或空json代替() {
    for body in [
        "<html>门户首页</html>",
        "{}",
        "[]",
        "",
        r#"{"code":"1","datas":{"userId":"synthetic"}}"#,
        r#"{"code":"0","datas":null}"#,
        r#"{"code":"0","data":{"userId":"synthetic"}}"#,
        r#"{"code":"0","datas":{}}"#,
        r#"{"code":"0","datas":{"userId":" "}}"#,
        r#"{"code":"0","datas":{"userId":true}}"#,
    ] {
        let response = HttpResponse::new(200, CURRENT_USER_URL, body.as_bytes().to_vec());
        assert_eq!(
            classify_undergraduate_portal(&response).unwrap_err().code,
            ErrorCode::UpstreamChanged
        );
    }
}

#[test]
fn 门户成功必须来自本路线的currentuser接口() {
    let body = br#"{"code":"0","datas":{"userId":"synthetic"}}"#.to_vec();
    for url in [
        CURRENT_USER_URL.to_string(),
        to_webvpn_url(CURRENT_USER_URL).unwrap(),
    ] {
        assert!(classify_undergraduate_portal(&HttpResponse::new(200, url, body.clone())).is_ok());
    }
    for url in [
        "https://byxt.buaa.edu.cn/",
        "https://uc.buaa.edu.cn/api/uc/status",
    ] {
        assert_eq!(
            classify_undergraduate_portal(&HttpResponse::new(200, url, body.clone()))
                .unwrap_err()
                .code,
            ErrorCode::UpstreamChanged
        );
    }
}
