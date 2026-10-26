use super::*;

#[test]
fn 博雅完整投影保留空值零考勤和完整点数且不传坐标() {
    let detail = domain::BykcCourseFullDetail {
        course: domain::BykcCourseCatalogItem {
            course: domain::BykcCourse {
                id: 71,
                ..Default::default()
            },
            category: Some(domain::BykcCourseCategory::Unknown),
            sub_category: Some(domain::BykcCourseSubCategory::Aesthetic),
            audience_campuses: vec!["未指定校区".into()],
            has_sign_points: true,
        },
        course_contact: Some("合成联系人".into()),
        course_contact_mobile: Some("000-TEST-01".into()),
        organizer_college_name: Some("合成单位".into()),
        description_plain_text: Some("纯文本\n第二行".into()),
        audience_colleges: vec!["合成学院".into()],
        audience_terms: vec![],
        audience_groups: vec!["合成人群".into()],
        sign_config: Some(domain::BykcSignConfig {
            sign_start_date: Some("2026-09-16T08:00:00".into()),
            sign_points: vec![
                domain::BykcSignPoint::default(),
                domain::BykcSignPoint::default(),
            ],
            ..Default::default()
        }),
        attendance: Some(domain::BykcCourseAttendanceDisplay {
            record_id: 7001,
            course_id: 71,
            checkin: Some(0),
            pass: None,
        }),
    };
    let mapped = super::super::mappers::map_bykc_full_detail(detail);
    assert!(matches!(
        mapped.course.category,
        Some(BridgeBykcCourseCategory::Unknown)
    ));
    assert!(matches!(
        mapped.course.sub_category,
        Some(BridgeBykcCourseSubCategory::Aesthetic)
    ));
    assert_eq!(mapped.course.audience_campuses, ["未指定校区"]);
    assert!(mapped.course.has_sign_points);
    assert_eq!(mapped.course_contact.as_deref(), Some("合成联系人"));
    assert_eq!(mapped.course_contact_mobile.as_deref(), Some("000-TEST-01"));
    assert_eq!(mapped.organizer_college_name.as_deref(), Some("合成单位"));
    assert_eq!(
        mapped.description_plain_text.as_deref(),
        Some("纯文本\n第二行")
    );
    assert_eq!(mapped.audience_colleges, ["合成学院"]);
    assert!(mapped.audience_terms.is_empty());
    assert_eq!(mapped.audience_groups, ["合成人群"]);
    let sign = mapped.sign_config.unwrap();
    assert_eq!(sign.sign_point_count, 2);
    assert_eq!(sign.sign_start_date.as_deref(), Some("2026-09-16T08:00:00"));
    assert!(
        sign.sign_end_date.is_none()
            && sign.sign_out_start_date.is_none()
            && sign.sign_out_end_date.is_none()
    );
    let attendance = mapped.attendance.unwrap();
    assert_eq!(
        (
            attendance.record_id,
            attendance.course_id,
            attendance.checkin,
            attendance.pass
        ),
        (7001, 71, Some(0), None)
    );
    let absent =
        super::super::mappers::map_bykc_full_detail(domain::BykcCourseFullDetail::default());
    assert!(absent.sign_config.is_none() && absent.attendance.is_none());
}
