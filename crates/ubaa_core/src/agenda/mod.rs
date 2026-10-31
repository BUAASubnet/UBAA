//! 本机日程服务，与学校网络和路线无关。
mod recurrence;
pub use recurrence::{expand_agenda, teaching_week_rule};
#[cfg(test)]
mod tests;

mod store;
pub use store::AgendaStore;
mod operations;
mod split;
