//! 图书馆座位、区域、预约与取消业务。
#![allow(clippy::missing_errors_doc)]

mod crypto;
mod parser;
mod service;

#[cfg(test)]
mod tests;

pub(crate) use crate::internal::route_state::LibBookCredential;

#[allow(unused_imports)]
pub use parser::{parse_area_detail_for, parse_areas, parse_libraries, parse_seats};
pub(crate) use service::{
    cancel_booking, get_area_detail, get_areas, get_bookings, get_libraries, get_seats,
    preflight_cancel, preflight_reserve, reserve,
};
