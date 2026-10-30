//! Fixture 保留真实响应信封，生产解析器只消费通过信封检查的数据。

use super::super::{catalog, parser};
use crate::{domain::*, error::Result};
use chrono::{Local, NaiveDateTime};

pub(super) fn parse_profile(body: &str) -> Result<BykcUserProfile> {
    parser::parse_profile(&parser::envelope(body)?)
}
pub(super) fn parse_courses(body: &str) -> Result<BykcCoursePage> {
    parse_courses_at(body, true, Local::now().naive_local())
}
pub(super) fn parse_courses_at(
    body: &str,
    all: bool,
    now: NaiveDateTime,
) -> Result<BykcCoursePage> {
    parser::parse_courses_at(&parser::envelope(body)?, all, now)
}
pub(crate) fn parse_course_detail(body: &str) -> Result<BykcCourse> {
    parser::parse_course_detail(&parser::envelope(body)?)
}
pub(super) fn parse_chosen_courses(body: &str) -> Result<Vec<BykcChosenCourse>> {
    parser::parse_chosen_courses(&parser::envelope(body)?)
}
pub(super) fn parse_chosen_courses_at(
    body: &str,
    now: NaiveDateTime,
) -> Result<Vec<BykcChosenCourse>> {
    parser::parse_chosen_courses_at(&parser::envelope(body)?, now)
}
pub(super) fn parse_statistics(body: &str) -> Result<BykcStatistics> {
    parser::parse_statistics(&parser::envelope(body)?)
}
pub(crate) fn parse_catalog_at(
    body: &str,
    all: bool,
    now: NaiveDateTime,
) -> Result<BykcCourseCatalogPage> {
    catalog::parse_catalog_at(&parser::envelope(body)?, all, now)
}
pub(crate) fn parse_full_detail(body: &str, id: i64) -> Result<BykcCourseFullDetail> {
    catalog::parse_full_detail(&parser::envelope(body)?, id)
}
