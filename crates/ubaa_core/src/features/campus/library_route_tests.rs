use super::*;

#[test]
fn 借阅列表仅将_webvpn_跳回图书馆原站识别为路线不支持() {
    let original = format!("{LIB_LIST}?page=1&pageSize=20");
    for (mode, location, code) in [
        (
            ConnectionMode::WebVpn,
            original.as_str(),
            crate::error::ErrorCode::PermissionDenied,
        ),
        (
            ConnectionMode::Direct,
            original.as_str(),
            crate::error::ErrorCode::UpstreamChanged,
        ),
        (
            ConnectionMode::WebVpn,
            "https://sso.buaa.edu.cn/login",
            crate::error::ErrorCode::UpstreamChanged,
        ),
    ] {
        let mut redirect = Step::redirect(&original, location);
        redirect.body = format!(r#"<a href="{location}">Found</a>"#);
        let (mut client, scenario, _) = runtime(mode, vec![redirect]);
        block_on_test(async {
            let error = super::super::super::current_loans(&mut client)
                .await
                .unwrap_err();
            assert_eq!(error.code, code);
        });
        assert_eq!(scenario.lock().unwrap().requests.len(), 1);
    }
}
