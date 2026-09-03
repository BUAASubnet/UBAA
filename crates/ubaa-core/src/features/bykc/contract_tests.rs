use super::{
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
