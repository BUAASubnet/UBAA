//! 仅供当前门锁页面使用的内存值，不实现序列化。
use std::fmt;

#[derive(Default)]
pub struct CgyyLockDisplay {
    pub code: Option<String>,
    pub due_date: Option<String>,
    pub reservation_reference: Option<String>,
    pub venue_name: Option<String>,
    pub site_name: Option<String>,
    pub space_name: Option<String>,
    pub order_name: Option<String>,
    pub reservation_date: Option<String>,
    pub reservation_date_detail: Option<String>,
    pub reservation_start_date: Option<String>,
    pub reservation_end_date: Option<String>,
}
impl fmt::Debug for CgyyLockDisplay {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("CgyyLockDisplay([REDACTED])")
    }
}
