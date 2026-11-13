use super::*;
use crate::domain::Term;
pub(super) const BODY: &str = r#"{
"code":1,"rwList":[{"BJDM":"sample","XNXQDM":"20261","SCSKRQ":"2026-09-14"}],
"jgList":[{"BJDM":"sample","KCDM":"demo","KCMC":"示例课程","XQ":1,"KSJCDM":1,"JSJCDM":2,"ZCBH":"0101","JCFADM":"01","JGJSXM":"示例教师"}],
"jcfaList":[{"skjcList":[{"JCFADM":"01","DM":"1","KSSJ":800,"JSSJ":845},{"JCFADM":"01","DM":"2","KSSJ":850,"JSSJ":935},{"JCFADM":"01","DM":"3","KSSJ":950,"JSSJ":1035}]}]}"#;
fn parse(body: &str) -> Result<GraduateSchedule> {
    parser::parse_schedule(
        body,
        vec![Term {
            item_code: "20261".into(),
            item_name: "示例学期".into(),
            selected: true,
            item_index: 0,
        }],
        "20261",
    )
}
#[test]
fn gsmis校历空周时间轴和今日保留冻结语义() {
    let value = parse(BODY).unwrap();
    let weeks = value.weeks("2026-09-08").unwrap();
    assert_eq!(weeks.len(), 4);
    assert_eq!(weeks[0].start_date, "2026-09-07");
    assert!(weeks[0].cur_week);
    let empty = value.weekly(1).unwrap();
    assert_eq!(empty.arranged_list.len(), 0);
    assert_eq!(empty.section_times.len(), 3);
    let course = value.weekly(2).unwrap().arranged_list.remove(0);
    assert_eq!(course.begin_time.as_deref(), Some("08:00"));
    assert_eq!(course.end_time.as_deref(), Some("09:35"));
    assert_eq!(course.end_section, Some(2));
    assert_eq!(course.weeks_and_teachers.as_deref(), Some("示例教师"));
    assert_eq!(value.today("2026-09-14").unwrap().len(), 1);
    assert_eq!(value.today("2026-09-15").unwrap().len(), 0);
    let serialized = serde_json::to_string(&empty).unwrap();
    assert_eq!(
        serde_json::from_str::<crate::domain::WeeklySchedule>(&serialized).unwrap(),
        empty
    );
}
#[test]
fn gsmis不猜日历学期节次或位图() {
    for invalid in [
        BODY.replace("2026-09-14", "2026-09-15"),
        BODY.replace("\"JSJCDM\":2", "\"JSJCDM\":4"),
        BODY.replace("\"code\":1", "\"code\":0"),
        BODY.replace("20261", "20253"),
        BODY.replace("0101", "01x1"),
        BODY.replace("\"XQ\":1", "\"XQ\":8"),
        BODY.replace("2026-09-14", ""),
        BODY.replace("\"KSSJ\":800", "\"KSSJ\":2560"),
    ] {
        assert!(parse(&invalid).is_err());
    }
    assert_eq!(
        parse(r#"{"code":1,"jgList":[],"rwList":[],"jcfaList":[]}"#)
            .unwrap()
            .weeks("2026-09-14")
            .unwrap()
            .len(),
        0
    );
}
#[test]
fn gsmis仅合并同班同方案相邻节次且去重() {
    let mut body: serde_json::Value = serde_json::from_str(BODY).unwrap();
    let row = body["jgList"][0].clone();
    body["jgList"].as_array_mut().unwrap().push(row.clone());
    let mut adjacent = row.clone();
    adjacent["KSJCDM"] = 3.into();
    adjacent["JSJCDM"] = 3.into();
    body["jgList"].as_array_mut().unwrap().push(adjacent);
    let merged = parse(&body.to_string()).unwrap().weekly(2).unwrap();
    assert_eq!(merged.arranged_list.len(), 1);
    assert_eq!(merged.arranged_list[0].end_section, Some(3));
    body["jgList"][2]["JASMC"] = "另一教室".into();
    assert_eq!(
        parse(&body.to_string())
            .unwrap()
            .weekly(2)
            .unwrap()
            .arranged_list
            .len(),
        2
    );
    let mut other = row;
    other["BJDM"] = "other".into();
    body["jgList"].as_array_mut().unwrap().push(other);
    let mut course = body["rwList"][0].clone();
    course["BJDM"] = "other".into();
    body["rwList"].as_array_mut().unwrap().push(course);
    assert_eq!(
        parse(&body.to_string())
            .unwrap()
            .weekly(2)
            .unwrap()
            .arranged_list
            .len(),
        3
    );
}

#[test]
fn gsmis缺失排课方案使用唯一声明并保留合并和时间轴() {
    for scheme in [
        None,
        Some(serde_json::Value::Null),
        Some("".into()),
        Some(" \t".into()),
    ] {
        let mut body: serde_json::Value =
            serde_json::from_str(&BODY.replace("\"01\"", "\"02\"")).unwrap();
        body["jcfaList"][0]["DM"] = "02".into();
        let mut adjacent = body["jgList"][0].clone();
        adjacent["KSJCDM"] = 3.into();
        adjacent["JSJCDM"] = 3.into();
        match scheme {
            Some(value) => adjacent["JCFADM"] = value,
            None => {
                adjacent.as_object_mut().unwrap().remove("JCFADM");
            }
        }
        body["jgList"].as_array_mut().unwrap().push(adjacent);
        let data = parse(&body.to_string()).expect("缺失编号应使用唯一声明方案");
        assert_eq!(
            data.weeks("2026-09-14").unwrap()[1].start_date,
            "2026-09-14"
        );
        let week = data.weekly(2).unwrap();
        assert_eq!(week.arranged_list.len(), 1);
        let course = &week.arranged_list[0];
        assert_eq!(course.begin_section, Some(1));
        assert_eq!(course.end_section, Some(3));
        assert_eq!(course.begin_time.as_deref(), Some("08:00"));
        assert_eq!(course.end_time.as_deref(), Some("10:35"));
        assert_eq!(data.today("2026-09-14").unwrap().len(), 1);
        assert_eq!(week.section_times.len(), 3);
        assert_eq!(data.weekly(1).unwrap().section_times, week.section_times);
    }
}

#[test]
fn gsmis缺失排课方案不能借用不明确的声明或不匹配的节次() {
    let mut body: serde_json::Value = serde_json::from_str(BODY).unwrap();
    body["jgList"][0]["JCFADM"] = serde_json::Value::Null;
    body["jcfaList"][0]["DM"] = "01".into();
    let mut invalid = Vec::new();
    for scheme in [
        None,
        Some(serde_json::Value::Null),
        Some("".into()),
        Some(" ".into()),
    ] {
        let mut value = body.clone();
        match scheme {
            Some(code) => value["jcfaList"][0]["DM"] = code,
            None => {
                value["jcfaList"][0].as_object_mut().unwrap().remove("DM");
            }
        }
        invalid.push(value);
    }
    let mut multiple = body.clone();
    multiple["jcfaList"]
        .as_array_mut()
        .unwrap()
        .push(serde_json::json!({"DM":"02","skjcList":[]}));
    invalid.push(multiple);
    let mut mismatched = body.clone();
    mismatched["jcfaList"][0]["skjcList"][0]["JCFADM"] = "02".into();
    invalid.push(mismatched);
    let mut missing_slot = body.clone();
    missing_slot["jcfaList"][0]["skjcList"]
        .as_array_mut()
        .unwrap()
        .remove(1);
    invalid.push(missing_slot);
    let mut duplicate_slot = body.clone();
    let slot = duplicate_slot["jcfaList"][0]["skjcList"][0].clone();
    duplicate_slot["jcfaList"][0]["skjcList"]
        .as_array_mut()
        .unwrap()
        .push(slot);
    invalid.push(duplicate_slot);
    for value in invalid {
        assert_eq!(
            parse(&value.to_string()).err().unwrap().code,
            crate::error::ErrorCode::UpstreamChanged
        );
    }
}

#[test]
fn gsmis明确排课方案保持原编号() {
    let mut body: serde_json::Value = serde_json::from_str(BODY).unwrap();
    body["jcfaList"][0]["DM"] = "01".into();
    body["jgList"][0]["JCFADM"] = "02".into();
    assert!(parse(&body.to_string()).is_err());
    body["jgList"][0]["JCFADM"] = "01".into();
    body["jcfaList"]
        .as_array_mut()
        .unwrap()
        .push(serde_json::json!({"DM":"02","skjcList":[]}));
    let week = parse(&body.to_string()).unwrap().weekly(2).unwrap();
    assert_eq!(week.arranged_list[0].begin_time.as_deref(), Some("08:00"));
    assert_eq!(week.section_times.len(), 3);
}
