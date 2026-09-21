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
        }
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
