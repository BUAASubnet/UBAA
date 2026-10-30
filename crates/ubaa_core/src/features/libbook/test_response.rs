//! Fixture 从原始信封进入，领域解析与完整度检查共用已核对的数据。

use super::{parser, schedule};
use crate::{domain::*, error::Result};

pub(super) fn parse_libraries(body: &str) -> Result<Vec<LibBookLibrary>> {
    Ok(parser::parse_libraries(&parser::envelope(body)?))
}
pub(super) fn parse_seats(body: &str) -> Result<Vec<LibBookSeat>> {
    Ok(parser::parse_seats(&parser::envelope(body)?))
}
pub(super) fn parse_area_detail_for(area_id: &str, body: &str) -> Result<LibBookAreaDetail> {
    parser::parse_area_detail_for(area_id, &parser::envelope(body)?)
}
pub(super) fn parse_area_detail_for_day(
    area_id: &str,
    day: &str,
    body: &str,
) -> Result<Option<LibBookAreaDetail>> {
    parser::parse_area_detail_for_day(area_id, day, &parser::envelope(body)?)
}
pub(super) fn parse_bookings_for_request(
    body: &str,
    page: i32,
    limit: i32,
) -> Result<LibBookBookingsPage> {
    parser::parse_bookings_for_request(&parser::envelope(body)?, page, limit)
}
pub(super) fn parse_area_schedule_for(area_id: &str, body: &str) -> Result<LibBookAreaSchedule> {
    schedule::parse_area_schedule_for(area_id, &parser::envelope(body)?)
}
