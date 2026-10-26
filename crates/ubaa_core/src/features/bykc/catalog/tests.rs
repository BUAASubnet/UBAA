use chrono::NaiveDateTime;
use serde_json::{Value, json};

use super::{parse_catalog_at, parse_full_detail};
use crate::domain::{BykcCourseCategory, BykcCourseSubCategory};

fn wrapped(value: &Value) -> String {
    json!({"status":"0", "data":value}).to_string()
}

fn now() -> NaiveDateTime {
    NaiveDateTime::parse_from_str("2026-09-15 12:00:00", "%Y-%m-%d %H:%M:%S").unwrap()
}

fn sign_config() -> String {
    json!({
        "signStartDate":" 2026-09-16 08:00:00 ", "signEndDate":"无效时间",
        "signOutStartDate":"2026-09-16T10:30", "signOutEndDate":null,
        "signPointList":[{"lat":10.0,"lng":20.0},{"lat":30.0,"lng":40.0,"radius":-1.0}]
    })
    .to_string()
}

#[test]
fn 目录补充类别校区完整点数且服务器分页不变() {
    let body = wrapped(&json!({"content":[{
        "id":71,"courseName":"合成目录课程","courseNewKind1":{"kindName":" 博雅课程 "},
        "courseNewKind2":{"kindName":" 美育 "},
        "courseCampusList":[" 沙河校区 ","","全部校区","沙河校区","杭州校区"],
        "courseSignConfig":sign_config()
    }], "totalElements":103,"totalPages":6,"size":20,"number":2}));
    let result = parse_catalog_at(&body, true, now()).unwrap();
    let row = &result.content[0];
    assert_eq!(row.category, Some(BykcCourseCategory::Boya));
    assert_eq!(row.sub_category, Some(BykcCourseSubCategory::Aesthetic));
    assert_eq!(
        row.audience_campuses,
        ["沙河校区", "未指定校区", "杭州校区"]
    );
    assert!(row.has_sign_points, "零和负半径仍是已解析的点，不是写资格");
    assert_eq!(
        (
            result.total_elements,
            result.total_pages,
            result.size,
            result.number
        ),
        (103, 6, 20, 2)
    );
}

#[test]
fn 目录未知类别空校区与_all回退不猜测() {
    for (campuses, raw, expected) in [
        (json!([]), json!(" ALL "), vec!["未指定校区"]),
        (json!([" "]), json!("沙河"), vec![]),
        (Value::Null, Value::Null, vec![]),
        (json!(["学院路校区"]), json!("ALL"), vec!["学院路校区"]),
    ] {
        let body = wrapped(&json!({"content":[{"id":71,"courseName":"合成目录课程",
            "courseNewKind1":{"kindName":"陌生一级"},"courseNewKind2":{"kindName":"陌生二级"},
            "courseCampusList":campuses,"courseCampus":raw,"courseSignConfig":"坏配置"}]}));
        let result = parse_catalog_at(&body, true, now()).unwrap();
        let row = &result.content[0];
        assert_eq!(row.category, Some(BykcCourseCategory::Unknown));
        assert_eq!(row.sub_category, Some(BykcCourseSubCategory::Unknown));
        assert_eq!(row.audience_campuses, expected);
        assert!(!row.has_sign_points);
    }
    let empty = wrapped(&json!({"content":[{"id":72,"courseName":"合成空值",
        "courseNewKind1":{"kindName":" "},"courseNewKind2":null,"courseSignConfig":"{}"}]}));
    let row = parse_catalog_at(&empty, true, now())
        .unwrap()
        .content
        .remove(0);
    assert!(row.category.is_none() && row.sub_category.is_none() && !row.has_sign_points);
}

#[test]
fn 完整详情投影联系信息范围纯文本可空窗口并保留旧序列化() {
    let body = wrapped(
        &json!({"id":71,"courseName":"合成详情课程","selected":false,
        "courseContact":" 合成联系人 ","courseContactMobile":" 000-TEST-017#02 ",
        "courseBelongCollege":{"id":1,"collegeName":" 合成开课单位 "},
        "courseDesc":" <p>甲&nbsp;&lt;乙&gt;&amp;&quot;&#39;<br/>第二行  </p><p>第三行</p> ",
        "courseCollegeList":[" 合成学院 ","","合成学院"],
        "courseTermList":["合成年级甲"," 合成年级乙 "],"courseGroupList":[" ","合成人群"],
        "courseCampusList":["学院路校区"],"courseSignConfig":sign_config()}),
    );
    let detail = parse_full_detail(&body, 71).unwrap();
    assert_eq!(detail.course_contact.as_deref(), Some("合成联系人"));
    assert_eq!(
        detail.course_contact_mobile.as_deref(),
        Some("000-TEST-017#02")
    );
    assert_eq!(
        detail.organizer_college_name.as_deref(),
        Some("合成开课单位")
    );
    assert_eq!(
        detail.description_plain_text.as_deref(),
        Some("甲 <乙>&\"'\n第二行\n\n第三行")
    );
    assert_eq!(detail.audience_colleges, ["合成学院", "合成学院"]);
    assert_eq!(detail.audience_terms, ["合成年级甲", "合成年级乙"]);
    assert_eq!(detail.audience_groups, ["合成人群"]);
    let config = detail.sign_config.unwrap();
    assert_eq!(
        config.sign_start_date.as_deref(),
        Some("2026-09-16T08:00:00")
    );
    assert!(config.sign_end_date.is_none());
    assert_eq!(
        config.sign_out_start_date.as_deref(),
        Some("2026-09-16T10:30")
    );
    assert!(config.sign_out_end_date.is_none());
    assert_eq!(config.sign_points.len(), 2);
    assert!(detail.course.has_sign_points && detail.attendance.is_none());
    let old = super::super::parser::parse_course_detail(&body).unwrap();
    assert_eq!(detail.course.course, old);
    let keys = serde_json::to_value(old).unwrap();
    let mut actual = keys
        .as_object()
        .unwrap()
        .keys()
        .map(String::as_str)
        .collect::<Vec<_>>();
    actual.sort_unstable();
    let mut expected = vec![
        "id",
        "courseName",
        "coursePosition",
        "courseTeacher",
        "courseStartDate",
        "courseEndDate",
        "courseSelectStartDate",
        "courseSelectEndDate",
        "courseCancelEndDate",
        "courseMaxCount",
        "courseCurrentCount",
        "status",
        "selected",
        "selectEligibility",
        "deselectEligibility",
    ];
    expected.sort_unstable();
    assert_eq!(actual, expected);
}

#[test]
fn 完整详情空值不虚构并独立拒绝响应课程身份不符() {
    let body = wrapped(
        &json!({"id":71,"courseName":"合成空值课程","courseContact":" ",
        "courseContactMobile":null,"courseDesc":"<p> </p>",
        "courseBelongCollege":{"collegeName":" "},"courseSignConfig":"坏配置"}),
    );
    let detail = parse_full_detail(&body, 71).unwrap();
    assert!(detail.course_contact.is_none() && detail.course_contact_mobile.is_none());
    assert!(detail.organizer_college_name.is_none() && detail.description_plain_text.is_none());
    assert!(detail.sign_config.is_none() && detail.attendance.is_none());
    assert!(
        detail.audience_colleges.is_empty()
            && detail.audience_terms.is_empty()
            && detail.audience_groups.is_empty()
    );
    assert!(
        parse_full_detail(&body, 99).is_err(),
        "新接口不得把其他课程作为完整成功返回"
    );
    assert!(
        super::super::parser::parse_course_detail(&body).is_ok(),
        "旧接口合同不变"
    );
}

#[test]
fn 显示配置日期字段类型畸形时不视为有效签到点() {
    let raw = json!({"signStartDate": 42, "signPointList":[{"lat":10,"lng":20}]}).to_string();
    let body = wrapped(&json!({"id":71,"courseName":"合成配置类型","courseSignConfig":raw}));
    let detail = parse_full_detail(&body, 71).unwrap();
    assert!(detail.sign_config.is_none());
    assert!(!detail.course.has_sign_points);
}
