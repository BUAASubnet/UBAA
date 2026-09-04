use base64::{Engine as _, engine::general_purpose::STANDARD};
use chrono::NaiveDateTime;
use sha1::{Digest, Sha1};

use super::BykcCredential;
use super::auth::{LOGIN_URL, resolve_login_target};
use super::crypto::{decrypt_response, encrypt_request_with_key};
use super::parser::{
    parse_chosen_courses, parse_chosen_courses_at, parse_courses_at, parse_sign_config,
    resolve_current_semester,
};
use super::write::{resolve_sign_location, sign_location_requires_fallback, sign_payload};
use crate::connection::to_webvpn_url;
use crate::domain::{
    ActionEligibility, BykcCourseCategory, BykcCourseStatus, BykcCourseSubCategory, BykcSignRequest,
};

#[test]
fn webvpn_绝对跳转先还原为直连目标() {
    let final_url = to_webvpn_url(LOGIN_URL).expect("包装博雅登录地址");
    let target =
        to_webvpn_url("https://bykc.buaa.edu.cn/cas-login?token=已脱敏").expect("包装博雅回调地址");

    assert_eq!(
        resolve_login_target(&final_url, &target).expect("解析 WebVPN 跳转"),
        "https://bykc.buaa.edu.cn/cas-login?token=%E5%B7%B2%E8%84%B1%E6%95%8F"
    );
}

#[test]
fn webvpn_相对跳转按还原后的业务地址解析() {
    let final_url = to_webvpn_url(LOGIN_URL).expect("包装博雅登录地址");

    assert_eq!(
        resolve_login_target(&final_url, "/cas-login?token=已脱敏").expect("解析 WebVPN 相对跳转"),
        "https://bykc.buaa.edu.cn/cas-login?token=%E5%B7%B2%E8%84%B1%E6%95%8F"
    );
}

#[test]
fn 冻结摘要与加密正文向量保持一致() {
    assert_eq!(
        format!("{:x}", Sha1::digest(b"abc")),
        "a9993e364706816aba3e25717850c26c9cd0d89d"
    );
    let request = encrypt_request_with_key(
        r#"{"pageNumber":1,"pageSize":20}"#,
        1_700_000_000_000,
        *b"ABCDEFGHJKMNPQRS",
    )
    .unwrap();
    assert_eq!(request.ts, "1700000000000");
    assert_eq!(STANDARD.decode(&request.ak).unwrap().len(), 128);
    assert_eq!(STANDARD.decode(&request.sk).unwrap().len(), 128);
    assert_eq!(
        decrypt_response(&request.encrypted_data, &request.aes_key).unwrap(),
        r#"{"pageNumber":1,"pageSize":20}"#
    );
}

#[test]
fn 业务凭据调试输出隐藏令牌() {
    let text = format!(
        "{:?}",
        BykcCredential {
            token: "secret".into()
        }
    );
    assert!(!text.contains("secret"));
    assert!(text.contains("已隐藏"));
}

#[test]
fn 课程分页默认过滤已过期和选课结束项目() {
    let body = serde_json::json!({
        "status": "0",
        "data": {
            "content": [
                {"id": 1, "courseName": "已开课", "courseStartDate": "2026-01-01 08:00:00"},
                {"id": 2, "courseName": "已结束选课", "courseStartDate": "2026-09-01 08:00:00", "courseSelectEndDate": "2026-01-01 08:00:00"},
                {"id": 3, "courseName": "可选", "courseStartDate": "2026-09-01 08:00:00", "courseSelectEndDate": "2026-08-01 08:00:00"}
            ],
            "totalElements": 3,
            "totalPages": 1,
            "size": 20,
            "number": 1
        }
    })
    .to_string();
    let now = NaiveDateTime::parse_from_str("2026-07-01 12:00:00", "%Y-%m-%d %H:%M:%S")
        .expect("解析固定时间");

    let filtered = parse_courses_at(&body, false, now).expect("解析默认课程分页");
    let all = parse_courses_at(&body, true, now).expect("解析全部课程分页");

    assert_eq!(filtered.content.len(), 1);
    assert_eq!(filtered.content[0].status, BykcCourseStatus::Available);
    assert_eq!(filtered.total_elements, 3);
    assert_eq!(all.content.len(), 3);
}

#[test]
fn 博雅选课资格缺失关键字段时为_unknown() {
    let body = serde_json::json!({
        "status": "0",
        "data": {
            "content": [{"id": 9, "courseName": "字段不完整的课程"}],
            "totalElements": 1,
            "totalPages": 1,
            "size": 20,
            "number": 1
        }
    })
    .to_string();
    let now = NaiveDateTime::parse_from_str("2026-09-03 12:00:00", "%Y-%m-%d %H:%M:%S")
        .expect("解析固定时间");

    let course = parse_courses_at(&body, true, now)
        .expect("解析课程")
        .content
        .remove(0);
    let value = serde_json::to_value(course).expect("序列化稳定 DTO");

    assert_eq!(value["selectEligibility"], "unknown");
}

#[test]
fn 博雅选课资格仅在完整且当前可选时为_allowed() {
    let now = NaiveDateTime::parse_from_str("2026-09-03 12:00:00", "%Y-%m-%d %H:%M:%S")
        .expect("解析固定时间");
    let parse = |course: serde_json::Value| {
        let body = serde_json::json!({
            "status": "0",
            "data": {
                "content": [course],
                "totalElements": 1,
                "totalPages": 1,
                "size": 20,
                "number": 1
            }
        })
        .to_string();
        parse_courses_at(&body, true, now)
            .expect("解析课程")
            .content
            .remove(0)
            .select_eligibility
    };
    let course = |selected: bool, current: i32, start: &str, end: &str, course_start: &str| {
        serde_json::json!({
            "id": 9,
            "courseName": "选课资格课程",
            "courseStartDate": course_start,
            "courseSelectStartDate": start,
            "courseSelectEndDate": end,
            "courseMaxCount": 10,
            "courseCurrentCount": current,
            "selected": selected
        })
    };

    assert_eq!(
        parse(course(
            false,
            5,
            "2026-09-01 00:00:00",
            "2026-09-05 00:00:00",
            "2026-10-01 00:00:00"
        )),
        ActionEligibility::Allowed
    );
    for denied in [
        course(
            true,
            5,
            "2026-09-01 00:00:00",
            "2026-09-05 00:00:00",
            "2026-10-01 00:00:00",
        ),
        course(
            false,
            10,
            "2026-09-01 00:00:00",
            "2026-09-05 00:00:00",
            "2026-10-01 00:00:00",
        ),
        course(
            false,
            5,
            "2026-09-04 00:00:00",
            "2026-09-05 00:00:00",
            "2026-10-01 00:00:00",
        ),
        course(
            false,
            5,
            "2026-09-01 00:00:00",
            "2026-09-02 00:00:00",
            "2026-10-01 00:00:00",
        ),
        course(
            false,
            5,
            "2026-09-01 00:00:00",
            "2026-09-05 00:00:00",
            "2026-09-02 00:00:00",
        ),
    ] {
        assert_eq!(parse(denied), ActionEligibility::Denied);
    }
    assert_eq!(
        parse(course(
            false,
            5,
            "无法解析",
            "2026-09-05 00:00:00",
            "2026-10-01 00:00:00",
        )),
        ActionEligibility::Unknown
    );
}

#[test]
fn 博雅选课资格无法证明课程未开课时为_unknown() {
    let body = serde_json::json!({
        "status": "0",
        "data": {
            "content": [{
                "id": 9,
                "courseName": "缺少开课时间",
                "courseSelectStartDate": "2026-09-01 00:00:00",
                "courseSelectEndDate": "2026-09-05 00:00:00",
                "courseMaxCount": 10,
                "courseCurrentCount": 5,
                "selected": false
            }],
            "totalElements": 1,
            "totalPages": 1,
            "size": 20,
            "number": 1
        }
    })
    .to_string();
    let now = NaiveDateTime::parse_from_str("2026-09-03 12:00:00", "%Y-%m-%d %H:%M:%S")
        .expect("解析固定时间");

    let course = parse_courses_at(&body, true, now)
        .expect("解析课程")
        .content
        .remove(0);

    assert_eq!(course.select_eligibility, ActionEligibility::Unknown);
}

#[test]
fn 博雅退选资格仅在已选且课程尚未开始时为_allowed() {
    let now = NaiveDateTime::parse_from_str("2026-09-04 12:00:00", "%Y-%m-%d %H:%M:%S")
        .expect("解析固定时间");
    let parse = |course: serde_json::Value| {
        let body = serde_json::json!({
            "status": "0",
            "data": {
                "content": [course],
                "totalElements": 1,
                "totalPages": 1,
                "size": 20,
                "number": 1
            }
        })
        .to_string();
        let course = parse_courses_at(&body, true, now)
            .expect("解析课程")
            .content
            .remove(0);
        serde_json::to_value(course).expect("序列化稳定 DTO")
    };
    let course = |id: i64, selected: Option<bool>, start: Option<&str>| {
        let mut value = serde_json::json!({"id": id, "courseName": "退选资格课程"});
        let object = value.as_object_mut().expect("课程对象");
        if let Some(selected) = selected {
            object.insert("selected".to_owned(), serde_json::json!(selected));
        }
        if let Some(start) = start {
            object.insert("courseStartDate".to_owned(), serde_json::json!(start));
        }
        value
    };

    assert_eq!(
        parse(course(42, Some(true), Some("2026-09-05 00:00:00")))["deselectEligibility"],
        "allowed"
    );
    assert_eq!(
        parse(course(42, Some(true), Some("2026-09-04 12:00:00")))["deselectEligibility"],
        "allowed"
    );
    assert_eq!(
        parse(course(42, Some(false), None))["deselectEligibility"],
        "denied"
    );
    assert_eq!(
        parse(course(42, Some(true), Some("2026-09-04 11:59:59")))["deselectEligibility"],
        "denied"
    );
    for unknown in [
        course(42, Some(true), None),
        course(42, Some(true), Some("无法解析")),
        course(42, None, Some("2026-09-05 00:00:00")),
        course(0, Some(true), Some("2026-09-05 00:00:00")),
    ] {
        assert_eq!(parse(unknown)["deselectEligibility"], "unknown");
    }
    let mut expired_cancel = course(42, Some(true), Some("2026-09-05 00:00:00"));
    expired_cancel.as_object_mut().expect("课程对象").insert(
        "courseCancelEndDate".to_owned(),
        serde_json::json!("2026-09-01 00:00:00"),
    );
    assert_eq!(parse(expired_cancel)["deselectEligibility"], "allowed");
}

#[test]
fn 已选课程自动选择当前学期并回退到最新学期() {
    let config = serde_json::json!({
        "semester": [
            {"semesterStartDate": "2025-09-01 00:00:00", "semesterEndDate": "2026-01-31 23:59:59"},
            {"semesterStartDate": "2026-02-01 00:00:00", "semesterEndDate": "2026-07-31 23:59:59"}
        ]
    });
    let current = NaiveDateTime::parse_from_str("2026-03-01 12:00:00", "%Y-%m-%d %H:%M:%S")
        .expect("解析固定时间");
    let after = NaiveDateTime::parse_from_str("2026-08-01 12:00:00", "%Y-%m-%d %H:%M:%S")
        .expect("解析固定时间");

    assert_eq!(
        resolve_current_semester(&config, current).expect("选择当前学期"),
        (
            "2026-02-01 00:00:00".to_owned(),
            "2026-07-31 23:59:59".to_owned()
        )
    );
    assert_eq!(
        resolve_current_semester(&config, after).expect("选择最新学期"),
        (
            "2026-02-01 00:00:00".to_owned(),
            "2026-07-31 23:59:59".to_owned()
        )
    );
    assert_eq!(
        resolve_current_semester(&serde_json::json!({"semester": []}), current)
            .expect_err("空学期必须失败")
            .message,
        "无法获取当前学期信息"
    );
}

#[test]
fn 已选课程展开课程签到和作业字段() {
    let body = serde_json::json!({
        "status": "0",
        "data": [{
            "id": 9,
            "selectDate": "2026-02-20 12:00:00",
            "checkin": 5,
            "score": 88,
            "pass": 0,
            "homework": "提交学习报告",
            "signInfo": "已签到",
            "courseInfo": {
                "id": 42,
                "courseName": "艺术鉴赏",
                "coursePosition": "学院路校区",
                "courseTeacher": "教师甲",
                "courseStartDate": "2026-03-01 08:00:00",
                "courseEndDate": "2026-03-01 10:00:00",
                "courseCancelEndDate": "2026-02-28 18:00:00",
                "courseNewKind1": {"kindName": "博雅课程"},
                "courseNewKind2": {"kindName": "美育"},
                "courseSignType": 1,
                "courseSignConfig": "{\"signStartDate\":\"2026-03-01 07:50:00\",\"signEndDate\":\"2026-03-01 08:10:00\",\"signOutStartDate\":\"2026-03-01 09:50:00\",\"signOutEndDate\":\"2026-03-01 10:10:00\",\"signPointList\":[{\"lat\":39.9,\"lng\":116.3,\"radius\":100.0}]}"
            }
        }]
    }).to_string();

    let record = parse_chosen_courses_at(
        &body,
        NaiveDateTime::parse_from_str("2026-03-01 10:00:00", "%Y-%m-%d %H:%M:%S")
            .expect("解析固定时间"),
    )
    .expect("解析已选课程")
    .remove(0);

    assert_eq!(record.course_id, 42);
    assert_eq!(record.course_name, "艺术鉴赏");
    assert_eq!(record.category, Some(BykcCourseCategory::Boya));
    assert_eq!(record.sub_category, Some(BykcCourseSubCategory::Aesthetic));
    assert_eq!(record.checkin, Some(5));
    assert_eq!(record.pass, Some(0));
    assert_eq!(record.sign_eligibility, ActionEligibility::Denied);
    assert_eq!(record.sign_out_eligibility, ActionEligibility::Allowed);
    assert_eq!(record.sign_config.expect("签到配置").sign_points.len(), 1);
    assert_eq!(record.homework.as_deref(), Some("提交学习报告"));
    assert_eq!(record.sign_info.as_deref(), Some("已签到"));
}

#[test]
fn 博雅签到与签退资格区分允许拒绝和未知() {
    let parse = |checkin: Option<i32>, pass: Option<i32>, config: Option<&str>, now: &str| {
        let mut chosen = serde_json::json!({
            "id": 9,
            "courseInfo": {"id": 42, "courseName": "资格课程"}
        });
        let object = chosen.as_object_mut().expect("已选课程对象");
        if let Some(checkin) = checkin {
            object.insert("checkin".to_owned(), serde_json::json!(checkin));
        }
        if let Some(pass) = pass {
            object.insert("pass".to_owned(), serde_json::json!(pass));
        }
        if let Some(config) = config {
            object
                .get_mut("courseInfo")
                .and_then(serde_json::Value::as_object_mut)
                .expect("课程对象")
                .insert("courseSignConfig".to_owned(), serde_json::json!(config));
        }
        let body = serde_json::json!({"status":"0", "data":[chosen]}).to_string();
        parse_chosen_courses_at(
            &body,
            NaiveDateTime::parse_from_str(now, "%Y-%m-%d %H:%M:%S").expect("固定时间"),
        )
        .expect("解析已选课程")
        .remove(0)
    };
    let config = serde_json::json!({
        "signStartDate": "2026-09-04 08:50:00",
        "signEndDate": "2026-09-04 09:10:00",
        "signOutStartDate": "2026-09-04 09:50:00",
        "signOutEndDate": "2026-09-04 10:10:00",
        "signPointList": [{"lat": 39.9, "lng": 116.3, "radius": 100.0}]
    })
    .to_string();
    let inverted_config = serde_json::json!({
        "signStartDate": "2026-09-04 09:10:00",
        "signEndDate": "2026-09-04 08:50:00",
        "signOutStartDate": "2026-09-04 10:10:00",
        "signOutEndDate": "2026-09-04 09:50:00",
        "signPointList": [{"lat": 39.9, "lng": 116.3, "radius": 100.0}]
    })
    .to_string();

    let signing = parse(Some(0), Some(0), Some(&config), "2026-09-04 08:50:00");
    assert_eq!(signing.sign_eligibility, ActionEligibility::Allowed);
    assert_eq!(signing.sign_out_eligibility, ActionEligibility::Denied);

    let signing_out = parse(Some(5), Some(0), Some(&config), "2026-09-04 10:10:00");
    assert_eq!(signing_out.sign_eligibility, ActionEligibility::Denied);
    assert_eq!(signing_out.sign_out_eligibility, ActionEligibility::Allowed);

    let outside = parse(Some(0), Some(0), Some(&config), "2026-09-04 12:00:00");
    assert_eq!(outside.sign_eligibility, ActionEligibility::Denied);
    assert_eq!(outside.sign_out_eligibility, ActionEligibility::Denied);

    let passed = parse(Some(0), Some(1), Some(&config), "2026-09-04 09:00:00");
    assert_eq!(passed.sign_eligibility, ActionEligibility::Denied);
    assert_eq!(passed.sign_out_eligibility, ActionEligibility::Denied);

    for unknown in [
        parse(None, Some(0), Some(&config), "2026-09-04 09:00:00"),
        parse(Some(0), None, Some(&config), "2026-09-04 09:00:00"),
        parse(Some(0), Some(0), None, "2026-09-04 09:00:00"),
        parse(Some(0), Some(0), Some("{not-json"), "2026-09-04 09:00:00"),
        parse(
            Some(0),
            Some(0),
            Some(&inverted_config),
            "2026-09-04 09:00:00",
        ),
    ] {
        assert_eq!(unknown.sign_eligibility, ActionEligibility::Unknown);
        assert_eq!(unknown.sign_out_eligibility, ActionEligibility::Unknown);
    }
}

#[test]
fn 博雅签到坐标遵循圆内算法并在无正半径点时回退输入() {
    let config = crate::domain::BykcSignConfig {
        sign_points: vec![crate::domain::BykcSignPoint {
            lat: 39.9,
            lng: 116.3,
            radius: 100.0,
        }],
        ..crate::domain::BykcSignConfig::default()
    };
    for _ in 0..32 {
        let (lat, lng) = resolve_sign_location(&config, None, None).expect("生成圆内坐标");
        let north_meters = (lat - 39.9) * 111_320.0;
        let east_meters = (lng - 116.3) * 111_320.0 * 39.9_f64.to_radians().cos();
        assert!(north_meters.hypot(east_meters) <= 100.1);
    }

    let no_radius = crate::domain::BykcSignConfig {
        sign_points: vec![crate::domain::BykcSignPoint {
            lat: 39.9,
            lng: 116.3,
            radius: 0.0,
        }],
        ..crate::domain::BykcSignConfig::default()
    };
    assert_eq!(
        resolve_sign_location(&no_radius, Some(40.0), Some(116.4)).expect("使用完整回退坐标"),
        (40.0, 116.4)
    );
    assert!(resolve_sign_location(&no_radius, None, None).is_err());

    let mixed = crate::domain::BykcSignConfig {
        sign_points: vec![
            config.sign_points[0].clone(),
            no_radius.sign_points[0].clone(),
        ],
        ..crate::domain::BykcSignConfig::default()
    };
    assert!(!sign_location_requires_fallback(&config));
    assert!(sign_location_requires_fallback(&no_radius));
    assert!(sign_location_requires_fallback(&mixed));

    for invalid_point in [
        crate::domain::BykcSignPoint {
            lat: 39.9,
            lng: 116.3,
            radius: f64::NAN,
        },
        crate::domain::BykcSignPoint {
            lat: 39.9,
            lng: 116.3,
            radius: f64::INFINITY,
        },
        crate::domain::BykcSignPoint {
            lat: f64::NAN,
            lng: 116.3,
            radius: 100.0,
        },
        crate::domain::BykcSignPoint {
            lat: 39.9,
            lng: 181.0,
            radius: 100.0,
        },
    ] {
        let invalid = crate::domain::BykcSignConfig {
            sign_points: vec![invalid_point],
            ..crate::domain::BykcSignConfig::default()
        };
        assert!(sign_location_requires_fallback(&invalid));
        assert_eq!(
            resolve_sign_location(&invalid, Some(40.0), Some(116.4))
                .expect("非法签到点必须使用完整回退坐标"),
            (40.0, 116.4)
        );
    }
}

#[test]
fn 博雅签到请求使用冻结的坐标字段名() {
    let request = BykcSignRequest {
        course_id: 42,
        lat: Some(39.9),
        lng: Some(116.3),
        sign_type: 1,
    };
    let host_value = serde_json::to_value(&request).expect("序列化宿主请求");
    assert_eq!(host_value["lat"], 39.9);
    assert_eq!(host_value["lng"], 116.3);

    let value = sign_payload(&request, 39.9, 116.3);

    assert_eq!(value["courseId"], 42);
    assert_eq!(value["signLat"], 39.9);
    assert_eq!(value["signLng"], 116.3);
    assert_eq!(value["signType"], 1);
    assert!(value.get("lat").is_none());
    assert!(value.get("lng").is_none());
}

#[test]
fn 已选课程接受冻结的_course_list_响应包装() {
    let body = serde_json::json!({
        "status": "0",
        "data": {
            "courseList": [{
                "id": 9001,
                "courseInfo": {
                    "id": 9527,
                    "courseName": "耕趣农场劳动课",
                    "courseStartDate": "2999-01-01 08:00:00"
                }
            }, {
                "id": 9002,
                "courseInfo": {"courseName": "缺少课程标识"}
            }]
        }
    })
    .to_string();
    let result = parse_chosen_courses(&body).expect("冻结 courseList 包装应可解析");
    assert_eq!(result.len(), 2);
    assert_eq!(result[0].id, 9001);
    assert_eq!(result[0].course_id, 9527);
    assert_eq!(result[0].deselect_eligibility, ActionEligibility::Allowed);
    assert_eq!(result[1].course_id, 0);
    assert_eq!(result[1].deselect_eligibility, ActionEligibility::Unknown);
}

#[test]
fn 签到配置包含无效签到点时整体解析失败() {
    let raw = serde_json::json!({
        "signStartDate": "2026-03-01 07:50:00",
        "signPointList": [{"lat": "invalid", "lng": 116.3}]
    })
    .to_string();

    assert!(parse_sign_config(&raw).is_none());
}

mod contract {
    use super::super::{
        parse_chosen_courses, parse_course_detail, parse_courses, parse_profile, parse_statistics,
    };

    #[test]
    fn 博雅解析五类只读响应并拒绝失败包装() {
        let profile =
            parse_profile(r#"{"status":"0","data":{"id":7,"employeeId":"e","realName":"张三"}}"#)
                .unwrap();
        assert_eq!(profile.id, 7);
        let courses = parse_courses(r#"{"status":"0","data":{"content":[{"id":9,"courseName":"课程"}],"totalElements":1,"totalPages":1,"size":20,"number":0}}"#).unwrap();
        assert_eq!(courses.content[0].course_name, "课程");
        assert_eq!(
            parse_course_detail(r#"{"status":"0","data":{"id":9,"courseName":"课程"}}"#)
                .unwrap()
                .id,
            9
        );
        assert_eq!(
            parse_chosen_courses(
                r#"{"status":"0","data":[{"id":1,"courseInfo":{"id":9,"courseName":"课程"}}]}"#
            )
            .unwrap()[0]
                .course_id,
            9
        );
        assert_eq!(
            parse_statistics(r#"{"status":"0","data":{"totalValidCount":2,"categories":[]}}"#)
                .unwrap()
                .total_valid_count,
            Some(2)
        );
        assert!(parse_profile(r#"{"status":"1","msg":"失败"}"#).is_err());
    }
}
