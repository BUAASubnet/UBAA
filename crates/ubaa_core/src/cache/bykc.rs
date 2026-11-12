//! 博雅持久投影不包含学校写资格、签到位置或原始响应。
use crate::domain::{
    BykcChosenCourse, BykcCourse, BykcCourseCategory, BykcCoursePage, BykcCourseStatus,
    BykcCourseSubCategory, BykcSignConfig,
};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedBykcCourse {
    pub id: i64,
    pub course_name: String,
    pub course_position: Option<String>,
    pub course_teacher: Option<String>,
    pub course_start_date: Option<String>,
    pub course_end_date: Option<String>,
    pub course_select_start_date: Option<String>,
    pub course_select_end_date: Option<String>,
    pub course_cancel_end_date: Option<String>,
    pub course_max_count: Option<i32>,
    pub course_current_count: Option<i32>,
    pub status: BykcCourseStatus,
    pub selected: Option<bool>,
    #[serde(default)]
    pub category: Option<BykcCourseCategory>,
    #[serde(default)]
    pub sub_category: Option<BykcCourseSubCategory>,
    #[serde(default)]
    pub audience_campuses: Option<Vec<String>>,
    #[serde(default)]
    pub has_sign_points: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub supplement: Option<Box<CachedBykcSupplement>>,
}
impl From<BykcCourse> for CachedBykcCourse {
    fn from(value: BykcCourse) -> Self {
        Self {
            id: value.id,
            course_name: value.course_name,
            course_position: value.course_position,
            course_teacher: value.course_teacher,
            course_start_date: value.course_start_date,
            course_end_date: value.course_end_date,
            course_select_start_date: value.course_select_start_date,
            course_select_end_date: value.course_select_end_date,
            course_cancel_end_date: value.course_cancel_end_date,
            course_max_count: value.course_max_count,
            course_current_count: value.course_current_count,
            status: value.status,
            selected: value.selected,
            category: None,
            sub_category: None,
            audience_campuses: None,
            has_sign_points: None,
            supplement: None,
        }
    }
}

/// 完整详情的可阅读补充，不包含签到坐标或写操作资格。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedBykcSupplement {
    pub course_contact: Option<String>,
    pub course_contact_mobile: Option<String>,
    pub organizer_college_name: Option<String>,
    pub description_plain_text: Option<String>,
    pub audience_colleges: Vec<String>,
    pub audience_terms: Vec<String>,
    pub audience_groups: Vec<String>,
    pub sign_config: Option<CachedBykcSignDisplay>,
    pub attendance: Option<crate::domain::BykcCourseAttendanceDisplay>,
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedBykcSignDisplay {
    pub sign_start_date: Option<String>,
    pub sign_end_date: Option<String>,
    pub sign_out_start_date: Option<String>,
    pub sign_out_end_date: Option<String>,
    pub sign_point_count: usize,
}

impl From<crate::domain::BykcCourseFullDetail> for CachedBykcCourse {
    fn from(value: crate::domain::BykcCourseFullDetail) -> Self {
        let mut course = Self::from(value.course);
        course.supplement = Some(Box::new(CachedBykcSupplement {
            course_contact: value.course_contact,
            course_contact_mobile: value.course_contact_mobile,
            organizer_college_name: value.organizer_college_name,
            description_plain_text: value.description_plain_text,
            audience_colleges: value.audience_colleges,
            audience_terms: value.audience_terms,
            audience_groups: value.audience_groups,
            attendance: value.attendance,
            sign_config: value.sign_config.map(|config| CachedBykcSignDisplay {
                sign_start_date: config.sign_start_date,
                sign_end_date: config.sign_end_date,
                sign_out_start_date: config.sign_out_start_date,
                sign_out_end_date: config.sign_out_end_date,
                sign_point_count: config.sign_points.len(),
            }),
        }));
        course
    }
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedBykcChosenCourse {
    pub id: i64,
    pub course_id: i64,
    pub course_name: String,
    pub course_position: Option<String>,
    pub course_teacher: Option<String>,
    pub course_start_date: Option<String>,
    pub course_end_date: Option<String>,
    pub select_date: Option<String>,
    pub course_cancel_end_date: Option<String>,
    pub category: Option<BykcCourseCategory>,
    pub sub_category: Option<BykcCourseSubCategory>,
    pub checkin: Option<i32>,
    pub score: Option<i32>,
    pub pass: Option<i32>,
    pub course_sign_type: Option<i32>,
    pub homework: Option<String>,
    pub homework_attachment_name: Option<String>,
    pub sign_window: Option<CachedBykcSignWindow>,
}
impl From<BykcChosenCourse> for CachedBykcChosenCourse {
    fn from(value: BykcChosenCourse) -> Self {
        Self {
            id: value.id,
            course_id: value.course_id,
            course_name: value.course_name,
            course_position: value.course_position,
            course_teacher: value.course_teacher,
            course_start_date: value.course_start_date,
            course_end_date: value.course_end_date,
            select_date: value.select_date,
            course_cancel_end_date: value.course_cancel_end_date,
            category: value.category,
            sub_category: value.sub_category,
            checkin: value.checkin,
            score: value.score,
            pass: value.pass,
            course_sign_type: value.course_sign_type,
            homework: value.homework,
            homework_attachment_name: value.homework_attachment_name,
            sign_window: value.sign_config.map(Into::into),
        }
    }
}

/// 仅学校公布的时间窗和范围存在性，不保存用户或学校坐标。
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedBykcSignWindow {
    pub sign_start_date: Option<String>,
    pub sign_end_date: Option<String>,
    pub sign_out_start_date: Option<String>,
    pub sign_out_end_date: Option<String>,
    pub has_points: bool,
}
impl From<BykcSignConfig> for CachedBykcSignWindow {
    fn from(v: BykcSignConfig) -> Self {
        Self {
            sign_start_date: v.sign_start_date,
            sign_end_date: v.sign_end_date,
            sign_out_start_date: v.sign_out_start_date,
            sign_out_end_date: v.sign_out_end_date,
            has_points: !v.sign_points.is_empty(),
        }
    }
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedBykcCoursePage {
    pub content: Vec<CachedBykcCourse>,
    pub total_elements: i32,
    pub total_pages: i32,
    pub size: i32,
    pub number: i32,
}
impl From<BykcCoursePage> for CachedBykcCoursePage {
    fn from(v: BykcCoursePage) -> Self {
        Self {
            content: v.content.into_iter().map(Into::into).collect(),
            total_elements: v.total_elements,
            total_pages: v.total_pages,
            size: v.size,
            number: v.number,
        }
    }
}
/// 当前已选视图保存本次真实请求日期范围，不猜测学期代码。
#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedBykcChosen {
    pub semester_start: String,
    pub semester_end: String,
    pub courses: Vec<CachedBykcChosenCourse>,
}

impl From<crate::domain::BykcCourseCatalogItem> for CachedBykcCourse {
    fn from(value: crate::domain::BykcCourseCatalogItem) -> Self {
        let mut course = Self::from(value.course);
        course.category = value.category;
        course.sub_category = value.sub_category;
        course.audience_campuses = Some(value.audience_campuses);
        course.has_sign_points = Some(value.has_sign_points);
        course
    }
}
impl From<crate::domain::BykcCourseCatalogPage> for CachedBykcCoursePage {
    fn from(value: crate::domain::BykcCourseCatalogPage) -> Self {
        Self {
            content: value.content.into_iter().map(Into::into).collect(),
            total_elements: value.total_elements,
            total_pages: value.total_pages,
            size: value.size,
            number: value.number,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 完整详情补充可往返且旧缓存缺补充仍可读取() {
        let mut full = crate::domain::BykcCourseFullDetail::default();
        full.course.course.id = 42;
        full.description_plain_text = Some("合成简介\n第二段".into());
        full.course_contact = Some("合成联系人".into());
        full.organizer_college_name = Some("合成单位".into());
        full.audience_colleges = vec!["合成学院".into()];
        full.sign_config = Some(BykcSignConfig {
            sign_start_date: Some("2026-11-12 08:00:00".into()),
            sign_points: vec![crate::domain::BykcSignPoint::default(); 2],
            ..Default::default()
        });
        full.attendance = Some(crate::domain::BykcCourseAttendanceDisplay {
            record_id: 1,
            course_id: 42,
            checkin: Some(0),
            pass: None,
        });
        let cached = CachedBykcCourse::from(full);
        let serialized = serde_json::to_value(&cached).unwrap();
        assert_eq!(
            serde_json::from_value::<CachedBykcCourse>(serialized.clone()).unwrap(),
            cached
        );
        let supplement = cached.supplement.as_ref().unwrap();
        assert_eq!(
            supplement.description_plain_text.as_deref(),
            Some("合成简介\n第二段")
        );
        assert_eq!(supplement.sign_config.as_ref().unwrap().sign_point_count, 2);
        assert_eq!(supplement.attendance.as_ref().unwrap().checkin, Some(0));
        let text = serialized.to_string();
        assert!(
            !text.contains("\"sign_points\"")
                && !text.contains("\"lat\"")
                && !text.contains("\"lng\"")
                && !text.contains("eligibility")
        );
        let mut legacy = serialized;
        legacy.as_object_mut().unwrap().remove("supplement");
        let legacy: CachedBykcCourse = serde_json::from_value(legacy).unwrap();
        assert_eq!(legacy.id, 42);
        assert!(legacy.supplement.is_none());
    }
}
