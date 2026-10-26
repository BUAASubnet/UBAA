//! 研讨室持久白名单以既有公开展示字段为上限；没有操作资格或内部订单材料。
use crate::domain::{
    CgyyDayInfo, CgyyOrder, CgyyOrdersPage, CgyySlotStatus, CgyySpaceAvailability, CgyyTimeSlot,
};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedCgyySlotStatus {
    pub time_id: i32,
    pub reservation_status: Option<i32>,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
}
impl From<CgyySlotStatus> for CachedCgyySlotStatus {
    fn from(v: CgyySlotStatus) -> Self {
        Self {
            time_id: v.time_id,
            reservation_status: v.reservation_status,
            start_date: v.start_date,
            end_date: v.end_date,
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedCgyySpaceAvailability {
    pub space_id: i32,
    pub space_name: String,
    pub venue_site_id: i32,
    pub venue_space_group_id: Option<i32>,
    pub slots: Vec<CachedCgyySlotStatus>,
}
impl From<CgyySpaceAvailability> for CachedCgyySpaceAvailability {
    fn from(v: CgyySpaceAvailability) -> Self {
        Self {
            space_id: v.space_id,
            space_name: v.space_name,
            venue_site_id: v.venue_site_id,
            venue_space_group_id: v.venue_space_group_id,
            slots: v.slots.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedCgyyDayInfo {
    pub venue_site_id: i32,
    pub reservation_date: String,
    pub available_dates: Vec<String>,
    pub time_slots: Vec<CgyyTimeSlot>,
    pub spaces: Vec<CachedCgyySpaceAvailability>,
    pub reservation_total_num: Option<i32>,
}
impl From<CgyyDayInfo> for CachedCgyyDayInfo {
    fn from(v: CgyyDayInfo) -> Self {
        Self {
            venue_site_id: v.venue_site_id,
            reservation_date: v.reservation_date,
            available_dates: v.available_dates,
            time_slots: v.time_slots,
            spaces: v.spaces.into_iter().map(Into::into).collect(),
            reservation_total_num: v.reservation_total_num,
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedCgyyOrder {
    pub id: i32,
    pub venue_site_id: Option<i32>,
    pub reservation_date: Option<String>,
    pub reservation_date_detail: Option<String>,
    pub venue_space_name: Option<String>,
    pub campus_name: Option<String>,
    pub venue_name: Option<String>,
    pub site_name: Option<String>,
    pub reservation_start_date: Option<String>,
    pub reservation_end_date: Option<String>,
    pub order_status: Option<i32>,
    pub check_status: Option<i32>,
    pub theme: Option<String>,
    pub purpose_type_name: Option<String>,
    pub joiner_num: Option<i32>,
}
impl From<CgyyOrder> for CachedCgyyOrder {
    fn from(v: CgyyOrder) -> Self {
        Self {
            id: v.id,
            venue_site_id: v.venue_site_id,
            reservation_date: v.reservation_date,
            reservation_date_detail: v.reservation_date_detail,
            venue_space_name: v.venue_space_name,
            campus_name: v.campus_name,
            venue_name: v.venue_name,
            site_name: v.site_name,
            reservation_start_date: v.reservation_start_date,
            reservation_end_date: v.reservation_end_date,
            order_status: v.order_status,
            check_status: v.check_status,
            theme: v.theme,
            purpose_type_name: v.purpose_type_name,
            joiner_num: v.joiner_num,
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedCgyyOrdersPage {
    pub content: Vec<CachedCgyyOrder>,
    pub total_elements: i32,
    pub total_pages: i32,
    pub size: i32,
    pub number: i32,
}
impl From<CgyyOrdersPage> for CachedCgyyOrdersPage {
    fn from(v: CgyyOrdersPage) -> Self {
        Self {
            content: v.content.into_iter().map(Into::into).collect(),
            total_elements: v.total_elements,
            total_pages: v.total_pages,
            size: v.size,
            number: v.number,
        }
    }
}
