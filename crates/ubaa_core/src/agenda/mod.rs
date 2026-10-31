//! 本机日程服务，与学校网络和路线无关。
mod recurrence;
pub use recurrence::{expand_agenda, teaching_week_rule};
#[cfg(test)]
mod tests;

mod store;
pub use store::AgendaStore;
mod operations;
mod split;

pub(crate) mod projection;
pub use projection::{SchoolAgendaContext, project_school_agenda};
mod query;
mod schedule;
#[cfg(test)]
mod schedule_tests;
mod school;
#[cfg(test)]
mod school_tests;

#[cfg(test)]
mod storage_tests;
#[cfg(test)]
pub(crate) mod test_fixture;

mod sqlite;
