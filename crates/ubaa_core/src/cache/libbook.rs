//! 图书馆只读展示白名单；状态不等于实时写资格。
use crate::domain::{LibBookBooking, LibBookBookingsPage, LibBookSeat};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedLibBookSeat {
    pub id: String,
    pub name: String,
    pub no: String,
    pub status: Option<i32>,
    pub status_name: String,
}
impl From<LibBookSeat> for CachedLibBookSeat {
    fn from(v: LibBookSeat) -> Self {
        Self {
            id: v.id,
            name: v.name,
            no: v.no,
            status: v.status,
            status_name: v.status_name,
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedLibBookBooking {
    pub id: String,
    pub name_merge: String,
    pub area_name: String,
    pub seat_no: String,
    pub day: String,
    pub begin_time: String,
    pub end_time: String,
    pub status: Option<i32>,
    pub status_name: String,
}
impl From<LibBookBooking> for CachedLibBookBooking {
    fn from(v: LibBookBooking) -> Self {
        Self {
            id: v.id,
            name_merge: v.name_merge,
            area_name: v.area_name,
            seat_no: v.seat_no,
            day: v.day,
            begin_time: v.begin_time,
            end_time: v.end_time,
            status: v.status,
            status_name: v.status_name,
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedLibBookBookingsPage {
    pub bookings: Vec<CachedLibBookBooking>,
    pub page: i32,
    pub limit: i32,
    pub total: i32,
}
impl From<LibBookBookingsPage> for CachedLibBookBookingsPage {
    fn from(v: LibBookBookingsPage) -> Self {
        Self {
            bookings: v.bookings.into_iter().map(Into::into).collect(),
            page: v.page,
            limit: v.limit,
            total: v.total,
        }
    }
}
