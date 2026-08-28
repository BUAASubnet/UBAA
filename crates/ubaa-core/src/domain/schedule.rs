use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Term {
    pub item_code: String,
    pub item_name: String,
    pub selected: bool,
    pub item_index: i32,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Week {
    pub start_date: String,
    pub end_date: String,
    pub term: String,
    pub cur_week: bool,
    pub serial_number: i32,
    pub name: String,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CourseClass {
    pub course_code: String,
    pub course_name: String,
    pub course_serial_no: Option<String>,
    pub credit: Option<String>,
    pub begin_time: Option<String>,
    pub end_time: Option<String>,
    pub begin_section: Option<i32>,
    pub end_section: Option<i32>,
    pub place_name: Option<String>,
    pub weeks_and_teachers: Option<String>,
    pub teaching_target: Option<String>,
    pub color: Option<String>,
    pub day_of_week: Option<i32>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WeeklySchedule {
    pub arranged_list: Vec<CourseClass>,
    pub code: String,
    pub name: String,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TodayClass {
    pub biz_name: String,
    pub place: Option<String>,
    pub time: Option<String>,
    pub short_name: Option<String>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExamArrangement {
    pub arranged: Vec<Exam>,
    pub not_arranged: Vec<Exam>,
}
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Exam {
    pub course_name: String,
    pub course_no: Option<String>,
    pub exam_time_description: Option<String>,
    pub exam_date: Option<String>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub exam_place: Option<String>,
    pub exam_seat_no: Option<String>,
    pub week: Option<i32>,
    pub exam_status: Option<i32>,
    pub exam_type: Option<String>,
    pub task_id: Option<String>,
}
