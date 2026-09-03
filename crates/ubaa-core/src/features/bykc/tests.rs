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
use crate::connection::to_webvpn_url;
use crate::domain::{
    ActionEligibility, BykcCourseCategory, BykcCourseStatus, BykcCourseSubCategory,
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
    assert_eq!(record.checkin, 5);
    assert_eq!(record.pass, Some(0));
    assert!(!record.can_sign);
    assert!(record.can_sign_out);
    assert_eq!(record.sign_config.expect("签到配置").sign_points.len(), 1);
    assert_eq!(record.homework.as_deref(), Some("提交学习报告"));
    assert_eq!(record.sign_info.as_deref(), Some("已签到"));
}

#[test]
fn 已选课程接受冻结的_course_list_响应包装() {
    let body = serde_json::json!({
        "status": "0",
        "data": {
            "courseList": [{
                "id": 9001,
                "courseInfo": {"id": 9527, "courseName": "耕趣农场劳动课"}
            }]
        }
    })
    .to_string();
    let result = parse_chosen_courses(&body).expect("冻结 courseList 包装应可解析");
    assert_eq!(result.len(), 1);
    assert_eq!(result[0].id, 9001);
    assert_eq!(result[0].course_id, 9527);
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
