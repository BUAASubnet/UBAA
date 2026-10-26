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
    assert!(empty.arranged_list.is_empty());
    assert_eq!(empty.section_times.len(), 3);
    let course = value.weekly(2).unwrap().arranged_list.remove(0);
    assert_eq!(course.begin_time.as_deref(), Some("08:00"));
    assert_eq!(course.end_time.as_deref(), Some("09:35"));
    assert_eq!(course.end_section, Some(2));
    assert_eq!(course.weeks_and_teachers.as_deref(), Some("示例教师"));
    assert_eq!(value.today("2026-09-14").unwrap().len(), 1);
    assert!(value.today("2026-09-15").unwrap().is_empty());
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
    assert!(
        parse(r#"{"code":1,"jgList":[],"rwList":[],"jcfaList":[]}"#)
            .unwrap()
            .weeks("2026-09-14")
            .unwrap()
            .is_empty()
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
