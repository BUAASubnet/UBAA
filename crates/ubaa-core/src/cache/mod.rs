//! 与网络客户端锁独立的本地业务缓存，不保存认证材料或写入资格。
mod cgyy;
pub use cgyy::{
    CachedCgyyDayInfo, CachedCgyyOrder, CachedCgyyOrdersPage, CachedCgyySlotStatus,
    CachedCgyySpaceAvailability,
};
mod bykc;
pub use bykc::{
    CachedBykcChosen, CachedBykcChosenCourse, CachedBykcCourse, CachedBykcCoursePage,
    CachedBykcSignWindow,
};
mod crypto;
mod files;
mod home;
pub use home::{CachedSigninClass, CachedYgdkItem, CachedYgdkOverview};
mod store;
mod types;

pub use crypto::CacheKey;
pub use store::{
    CacheClearReport, CacheInvalidation, CacheInvalidationReport, CacheRecovery, CacheUsage,
    OfflineRepository,
};
pub use types::*;

#[cfg(test)]
mod tests;

#[cfg(test)]
mod cgyy_tests;

#[cfg(test)]
mod libbook_tests;

mod libbook;
pub use libbook::{CachedLibBookBooking, CachedLibBookBookingsPage, CachedLibBookSeat};

mod evaluation;
pub use evaluation::{CachedEvaluationCourse, CachedEvaluationCourses};

mod ygdk_records;
pub use ygdk_records::{CachedYgdkRecord, CachedYgdkRecordsPage, CachedYgdkRecordsSelection};

mod profile;
pub use profile::CachedMaskedProfile;

mod schedule;
pub use schedule::CachedSemesterSchedule;
