//! 跨设备同步的文档、稳定记录版本及本机快照。
mod deletions;
mod document;
pub(crate) mod publication;
pub(super) mod sqlite;
mod state;
mod transaction;
pub(super) use state::{SyncState, track_local_changes};
mod values;
pub use deletions::{AgendaSyncItemDeletion, AgendaSyncOverlayDeletion};
pub use document::{AgendaSyncDocument, AgendaSyncItem, AgendaSyncOverlay};
pub use transaction::AgendaSyncSnapshot;
#[cfg(test)]
mod tests;

#[cfg(test)]
mod process_tests;
#[cfg(test)]
mod storage_tests;

pub(crate) mod coordinator;
pub use coordinator::{AgendaSyncAction, AgendaSyncReport, AgendaSyncStatus};
mod error;
pub use error::AgendaSyncError;
#[cfg(test)]
mod coordinator_tests;
