use super::captcha::{
    CgyyCaptchaChallenge, build_captcha_check_form, build_captcha_params, parse_captcha_challenge,
    solve_captcha_offset,
};
use super::crypto::build_captcha_solution;
use super::http::{check_business_response, safe_parameter_summary, safe_url, signed_request};
use super::parser::{parse_action_result, parse_sites};
use super::sign::sign;
use super::write::{build_submit_form, validate_submit_request};
use crate::domain::{CgyyReservationSelection, CgyyReservationSubmitRequest, ConnectionMode};
use crate::error::ErrorCode;
use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use crate::runtime::ClientRuntime;
use crate::session::FileSessionStore;
use async_trait::async_trait;

#[test]
fn 签名排除冻结审计字段() {
    let timestamp = 1_710_000_000_000;
    let mut noisy = std::collections::BTreeMap::from([
        ("a".to_owned(), "1".to_owned()),
        ("b".to_owned(), "2".to_owned()),
        ("id".to_owned(), "123".to_owned()),
        ("creator".to_owned(), "operator".to_owned()),
        ("gmtModified".to_owned(), "today".to_owned()),
    ]);
    let clean = std::collections::BTreeMap::from([
        ("a".to_owned(), "1".to_owned()),
        ("b".to_owned(), "2".to_owned()),
    ]);
    assert_eq!(
        sign("/api/test", &clean, timestamp),
        sign("/api/test", &noisy, timestamp)
    );
    noisy.insert("_rowKey".to_owned(), "row".to_owned());
    assert_eq!(
        sign("/api/test", &clean, timestamp),
        sign("/api/test", &noisy, timestamp)
    );
}

#[test]
fn 解析取消订单成功消息() {
    let result = parse_action_result(r#"{"code":200,"message":"取消成功","data":null}"#)
        .expect("应解析成功");
    assert_eq!(result.message, "取消成功");
    assert!(result.order.is_none());
}

#[test]
fn 场馆三百零二跳转到统一认证时识别为认证失效() {
    let mut response = HttpResponse::new(302, "https://cgyy.buaa.edu.cn/api/codes", Vec::new());
    response.headers.insert(
        "location".into(),
        vec!["https://sso.buaa.edu.cn/login".into()],
    );
    let error = check_business_response(&response, "场馆预约").expect_err("应识别认证跳转");
    assert_eq!(error.code, crate::error::ErrorCode::AuthenticationRequired);
}

#[test]
fn 日志摘要不包含参数值并隐藏动态路径段() {
    let params = std::collections::BTreeMap::from([
        ("venueSiteId".into(), "123".into()),
        ("searchDate".into(), "2026-08-31".into()),
        ("token".into(), "access-token-secret".into()),
    ]);
    let summary = safe_parameter_summary(&params);
    let rendered = format!("{summary:?}");
    assert!(!rendered.contains("123"));
    assert!(!rendered.contains("2026-08-31"));
    assert!(!rendered.contains("access-token-secret"));
    assert_eq!(
        safe_url("https://cgyy.buaa.edu.cn/api/orders/123"),
        "https://cgyy.buaa.edu.cn/api/orders/<id>"
    );
}

#[test]
fn 业务响应按旧版允许状态码异常但业务代码成功() {
    let response = HttpResponse::new(
        500,
        "https://cgyy.buaa.edu.cn/venue-zhjs-server/api/orders/mine",
        br#"{"code":200,"data":{"content":[]}}"#.to_vec(),
    );
    assert!(check_business_response(&response, "订单").is_ok());
}

#[test]
fn 场馆站点数字原语按冻结实现转为文本() {
    let body = r#"{"code":200,"data":[{"id":7,"siteName":8,"venueName":9,"campusName":10}]}"#;
    let sites = parse_sites(body).expect("解析站点");
    assert_eq!(sites[0].site_name, "8");
    assert_eq!(sites[0].venue_name, "9");
    assert_eq!(sites[0].campus_name, "10");
}

#[test]
fn 预约提交表单匹配冻结字段() {
    let request = CgyyReservationSubmitRequest {
        venue_site_id: 7,
        reservation_date: "2026-08-28".into(),
        selections: vec![CgyyReservationSelection {
            space_id: 11,
            time_id: 3,
            venue_space_group_id: None,
        }],
        phone: "010-00000000".into(),
        theme: "测试".into(),
        purpose_type: 1,
        joiner_num: 2,
        activity_content: "内容".into(),
        joiners: "甲,乙".into(),
        is_philosophy_social_sciences: false,
        is_off_school_joiner: true,
        captcha_verification: "verification".into(),
        captcha_point_json: "[{\"x\":1,\"y\":2}]".into(),
        captcha_token: "captcha-token".into(),
        captcha_secret_key: None,
        captcha_original_image_base64: None,
        captcha_jigsaw_image_base64: None,
    };
    let form = build_submit_form(&request, "token", "[{\"spaceId\":11,\"timeId\":3}]");
    assert_eq!(form.get("venueSiteId").map(String::as_str), Some("7"));
    assert_eq!(
        form.get("reservationOrderJson").map(String::as_str),
        Some("[{\"spaceId\":11,\"timeId\":3}]")
    );
    assert_eq!(
        form.get("isPhilosophySocialSciences").map(String::as_str),
        Some("0")
    );
    assert_eq!(form.get("isOffSchoolJoiner").map(String::as_str), Some("1"));
    assert_eq!(
        form.get("captchaVerification").map(String::as_str),
        Some("verification")
    );
    let captcha = build_captcha_check_form("points", "challenge");
    assert_eq!(captcha.get("pointJson").map(String::as_str), Some("points"));
    assert_eq!(captcha.get("token").map(String::as_str), Some("challenge"));
}

#[test]
fn 验证码挑战请求参数和响应字段匹配冻结协议() {
    let params = build_captcha_params(1234);
    assert_eq!(
        params.get("captchaType").map(String::as_str),
        Some("blockPuzzle")
    );
    assert_eq!(
        params.get("clientUid").map(String::as_str),
        Some("slider-1234")
    );
    assert_eq!(params.get("ts").map(String::as_str), Some("1234"));

    let challenge = parse_captcha_challenge(
        r#"{"code":200,"data":{"success":true,"repData":{"secretKey":"key","token":"token","originalImageBase64":"bg","jigsawImageBase64":"piece"}}}"#,
    )
    .expect("应解析验证码挑战");
    assert_eq!(challenge.secret_key, "key");
    assert_eq!(challenge.token, "token");
    assert_eq!(challenge.original_image_base64, "bg");
    assert_eq!(challenge.jigsaw_image_base64, "piece");
}

#[test]
fn 验证码挑战调试输出不泄露密钥令牌和图像() {
    let challenge = CgyyCaptchaChallenge {
        secret_key: "captcha-secret-key".into(),
        token: "captcha-session-token".into(),
        original_image_base64: "original-image-secret".into(),
        jigsaw_image_base64: "jigsaw-image-secret".into(),
    };
    let rendered = format!("{challenge:?}");
    assert!(!rendered.contains("captcha-secret-key"));
    assert!(!rendered.contains("captcha-session-token"));
    assert!(!rendered.contains("original-image-secret"));
    assert!(!rendered.contains("jigsaw-image-secret"));
}

#[test]
fn web_vpn模式下场馆签名请求使用_webvpn地址() {
    let root = std::env::temp_dir().join(format!("ubaa-cgyy-url-{}", std::process::id()));
    let runtime = ClientRuntime::new(
        ConnectionMode::WebVpn,
        NoNetworkTransport,
        FileSessionStore::new(&root).unwrap(),
    )
    .unwrap();
    let request = signed_request(
        &runtime,
        HttpMethod::Get,
        "/api/front/website/venues",
        std::collections::BTreeMap::new(),
        Some("token-safe"),
    )
    .unwrap();
    let url = url::Url::parse(&request.url).unwrap();
    assert_eq!(url.host_str(), Some("d.buaa.edu.cn"));
    let direct = crate::connection::from_webvpn_url(&request.url).unwrap();
    assert_eq!(
        url::Url::parse(&direct).unwrap().host_str(),
        Some("cgyy.buaa.edu.cn")
    );
    let _ = std::fs::remove_dir_all(root);
}

struct NoNetworkTransport;

#[async_trait]
impl HttpTransport for NoNetworkTransport {
    async fn execute(&self, _request: HttpRequest) -> crate::error::Result<HttpResponse> {
        panic!("请求构造测试不应访问网络");
    }
}

#[test]
fn 验证码位移凭据使用冻结_aes_ecb_pkcs7_向量() {
    let (point, verification) =
        build_captcha_solution("0123456789abcdef", "token", 12).expect("应生成验证码凭据");
    assert_eq!(point, "//vojImUw+QfCP7LYCytFg==");
    assert!(!verification.is_empty());
}

#[test]
fn 验证码位移求解拒绝非法图片() {
    assert!(solve_captcha_offset(b"not-an-image", b"not-an-image").is_err());
}

#[test]
fn 验证码位移求解匹配内存_png_图案() {
    use image::{DynamicImage, ImageFormat, Rgba, RgbaImage};
    use std::io::Cursor;

    fn encode(image: RgbaImage) -> Vec<u8> {
        let mut output = Cursor::new(Vec::new());
        DynamicImage::ImageRgba8(image)
            .write_to(&mut output, ImageFormat::Png)
            .expect("测试图片应可编码");
        output.into_inner()
    }

    let mut background = RgbaImage::from_pixel(64, 32, Rgba([255, 255, 255, 255]));
    let mut piece = RgbaImage::from_pixel(12, 12, Rgba([255, 255, 255, 0]));
    for y in 0..12 {
        for x in 0..12 {
            let border = x == 0 || y == 0 || x == 11 || y == 11;
            if border {
                piece.put_pixel(x, y, Rgba([0, 0, 0, 255]));
                background.put_pixel(30 + x, 10 + y, Rgba([0, 0, 0, 255]));
            }
        }
    }
    let offset = solve_captcha_offset(&encode(background), &encode(piece)).expect("应匹配测试滑块");
    // 算法匹配的是白色背景到黑色边框的边界，因此横坐标为 29。
    assert_eq!(offset, 29);
}

#[test]
fn 预约请求省略验证码时允许内部挑战流程() {
    let request = CgyyReservationSubmitRequest {
        venue_site_id: 4,
        reservation_date: "2026-03-29".into(),
        selections: vec![CgyyReservationSelection {
            space_id: 6,
            time_id: 242,
            venue_space_group_id: None,
        }],
        phone: "010-00000000".into(),
        theme: "测试预约".into(),
        purpose_type: 1,
        joiner_num: 1,
        activity_content: "测试内容".into(),
        joiners: "测试人员".into(),
        is_philosophy_social_sciences: false,
        is_off_school_joiner: false,
        ..Default::default()
    };

    assert!(validate_submit_request(&request).is_ok());
}

#[test]
fn 预约请求只提供部分内部验证码挑战时在网络前失败关闭() {
    let request = CgyyReservationSubmitRequest {
        venue_site_id: 4,
        reservation_date: "2026-03-29".into(),
        selections: vec![CgyyReservationSelection {
            space_id: 6,
            time_id: 242,
            venue_space_group_id: None,
        }],
        phone: "010-00000000".into(),
        theme: "测试预约".into(),
        purpose_type: 1,
        joiner_num: 1,
        activity_content: "测试内容".into(),
        joiners: "测试人员".into(),
        captcha_token: "captcha-token".into(),
        captcha_secret_key: Some("0123456789abcdef".into()),
        captcha_original_image_base64: Some("original-fixture".into()),
        captcha_jigsaw_image_base64: None,
        ..Default::default()
    };

    let error = validate_submit_request(&request).expect_err("不完整挑战材料必须失败关闭");
    assert_eq!(error.code, ErrorCode::InvalidInput);
}

#[test]
fn 预约请求_debug_隐藏全部敏感表单字段且保留安全结构元数据() {
    let request = CgyyReservationSubmitRequest {
        venue_site_id: 4,
        reservation_date: "2026-03-29".into(),
        selections: vec![CgyyReservationSelection {
            space_id: 6,
            time_id: 242,
            venue_space_group_id: Some(9),
        }],
        phone: "PHONE-SENTINEL-01000000000".into(),
        theme: "THEME-SENTINEL".into(),
        purpose_type: 1,
        joiner_num: 1,
        activity_content: "ACTIVITY-SENTINEL".into(),
        joiners: "JOINERS-SENTINEL".into(),
        is_philosophy_social_sciences: false,
        is_off_school_joiner: true,
        captcha_verification: "VERIFICATION-SENTINEL".into(),
        captcha_point_json: "POINT-SENTINEL".into(),
        captcha_token: "TOKEN-SENTINEL".into(),
        captcha_secret_key: Some("SECRET-SENTINEL".into()),
        captcha_original_image_base64: Some("ORIGINAL-IMAGE-SENTINEL".into()),
        captcha_jigsaw_image_base64: Some("JIGSAW-IMAGE-SENTINEL".into()),
    };

    let debug = format!("{request:?}");
    for sentinel in [
        "PHONE-SENTINEL-01000000000",
        "THEME-SENTINEL",
        "ACTIVITY-SENTINEL",
        "JOINERS-SENTINEL",
        "VERIFICATION-SENTINEL",
        "POINT-SENTINEL",
        "TOKEN-SENTINEL",
        "SECRET-SENTINEL",
        "ORIGINAL-IMAGE-SENTINEL",
        "JIGSAW-IMAGE-SENTINEL",
    ] {
        assert!(!debug.contains(sentinel), "Debug 泄漏了 {sentinel}");
    }
    for safe_metadata in [
        "venue_site_id: 4",
        "reservation_date: \"2026-03-29\"",
        "space_id: 6",
        "time_id: 242",
        "purpose_type: 1",
        "joiner_num: 1",
        "is_off_school_joiner: true",
    ] {
        assert!(debug.contains(safe_metadata), "Debug 缺少 {safe_metadata}");
    }
}

mod contract {
    use super::super::parser::{
        parse_day_context, parse_lock_code, parse_order_detail, parse_orders,
        parse_purpose_types_with_source, parse_sites,
    };

    #[test]
    fn 解析场馆站点和用途类型() {
        let sites = parse_sites(include_str!(
            "../../../../../fixtures/readonly/cgyy-sites.json"
        ))
        .unwrap();
        assert_eq!(sites[0].id, 4);
        assert_eq!(sites[0].site_name, "二层");
        let purposes = parse_purpose_types_with_source(r#"{"code":200,"data":[]}"#)
            .unwrap()
            .0;
        assert_eq!(purposes.len(), 10);
        assert_eq!(purposes[2].key, 3);
    }

    #[test]
    fn 场馆响应缺少或非二百代码时拒绝成功() {
        assert!(parse_sites(r#"{"data":[]}"#).is_err());
        assert!(parse_sites(r#"{"code":0,"data":[]}"#).is_err());
    }

    #[test]
    fn 旧版场馆包装会展开场馆下的站点列表() {
        let body = r#"{"code":200,"data":[{"id":9,"venueName":"沙河研讨室","campusName":"沙河校区","siteList":[{"id":"101","siteName":"一层"}]}]}"#;
        let sites = parse_sites(body).unwrap();
        assert_eq!(sites.len(), 1);
        assert_eq!(sites[0].id, 101);
        assert_eq!(sites[0].site_name, "一层");
        assert_eq!(sites[0].venue_name, "沙河研讨室");
        assert_eq!(sites[0].campus_name, "沙河校区");
    }

    #[test]
    fn 状态二的时段不可预约() {
        let body = include_str!("../../../../../fixtures/readonly/cgyy-day.json");
        let result = parse_day_context(body, 4, "2026-03-29").unwrap().info;
        assert_eq!(result.time_slots[0].label, "14:00-15:35");
        assert_eq!(result.spaces[0].slots[0].reservation_status, Some(2));
        assert_eq!(
            result.spaces[0].slots[0].reservation_eligibility,
            crate::domain::ActionEligibility::Denied
        );
        assert!(result.spaces[0].slots[0].reservation_target.is_none());
    }

    #[test]
    fn 日期空间槽位按时间编号排序() {
        let body = r#"{
            "code":200,
            "data":{
                "spaceTimeInfo":[
                    {"id":242,"beginTime":"14:00","endTime":"15:35"},
                    {"id":101,"beginTime":"08:00","endTime":"09:35"}
                ],
                "reservationDateSpaceInfo":{
                    "2026-03-29":[
                        {"id":6,"spaceName":"测试房间","101":{"reservationStatus":1},"242":{"reservationStatus":1}}
                    ]
                }
            }
        }"#;
        let result = parse_day_context(body, 4, "2026-03-29").unwrap().info;
        assert_eq!(
            result.spaces[0]
                .slots
                .iter()
                .map(|slot| slot.time_id)
                .collect::<Vec<_>>(),
            vec![101, 242]
        );
    }

    #[test]
    fn 预约上下文令牌不进入公共序列化输出() {
        let day = parse_day_context(
            r#"{"code":200,"data":{"token":"reservation-token"}}"#,
            4,
            "2026-03-29",
        )
        .unwrap()
        .info;
        let value = serde_json::to_value(day).unwrap();

        assert!(value.get("reservationToken").is_none());
        assert!(!value.to_string().contains("reservation-token"));
    }

    #[test]
    fn 解析订单分页和详情完整字段() {
        let body = include_str!("../../../../../fixtures/readonly/cgyy-orders.json");
        let page = parse_orders(body).unwrap();
        assert_eq!(
            page.content[0].purpose_type_name.as_deref(),
            Some("学术研讨类（竞赛、答辩、展示等小组讨论）")
        );
        assert_eq!(page.content[0].check_content.as_deref(), Some("材料不完整"));
        let detail =
            parse_order_detail(r#"{"code":200,"data":{"id":9,"theme":"课程讨论","joinerNum":3}}"#)
                .unwrap();
        assert_eq!(detail.theme.as_deref(), Some("课程讨论"));
        assert_eq!(detail.joiner_num, Some(3));
    }

    #[test]
    fn 成功订单空数据按冻结实现映射为空页和空详情() {
        let page = parse_orders(r#"{"code":200,"data":null}"#).unwrap();
        assert!(page.content.is_empty());
        assert_eq!(page.total_elements, 0);
        assert_eq!(page.size, 20);
        assert_eq!(page.number, 0);

        let detail = parse_order_detail(r#"{"code":200,"data":null}"#).unwrap();
        assert_eq!(detail.id, 0);
    }

    #[test]
    fn 订单缺少数据字段时按旧版映射为空对象() {
        let page =
            parse_orders(r#"{"code":200,"message":"OK","content":[{"id":99}],"totalElements":1}"#)
                .unwrap();
        assert!(page.content.is_empty());
        assert_eq!(page.total_elements, 0);

        let detail = parse_order_detail(r#"{"code":200,"message":"OK"}"#).unwrap();
        assert_eq!(detail.id, 0);
    }

    #[test]
    fn 锁码和日期响应遵守旧版成功信封与空数据语义() {
        assert!(parse_lock_code(r#"{"data":{"lockCode":"fixture"}}"#).is_err());
        assert!(parse_lock_code(r#"{"code":500,"data":{"lockCode":"fixture"}}"#).is_err());
        let empty_lock_code = parse_lock_code(r#"{"code":200,"data":null}"#).unwrap();
        assert!(!empty_lock_code.available);
        assert!(parse_day_context(r#"{"code":200}"#, 4, "2026-03-29").is_err());
    }

    #[test]
    fn 锁码公共序列化不暴露上游原始数据() {
        let lock_code =
            parse_lock_code(r#"{"code":200,"data":{"lockCode":"fixture-secret","orderId":7}}"#)
                .unwrap();
        let serialized = serde_json::to_string(&lock_code).unwrap();
        assert!(!serialized.contains("fixture-secret"));
        assert_eq!(
            serde_json::from_str::<serde_json::Value>(&serialized).unwrap(),
            serde_json::json!({"available": true})
        );
    }

    #[test]
    fn cgyy_lock_code_parser_returns_safe_availability_summary() {
        let result =
            parse_lock_code(r#"{"code":200,"data":{"orderId":7,"lockCode":"1234"}}"#).unwrap();
        assert!(result.available);
    }
}
