use super::AgendaSyncDocument;
use crate::cache::{CacheError, CacheResult};
use uuid::Uuid;

/// 准备阶段只选择操作；发布序号与正文由账号事务共同分配。
pub(super) enum SyncAttempt {
    Directory(String),
    Publication,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum PublicationReceipt {
    Unknown(Option<String>),
    Registered(String),
}

impl PublicationReceipt {
    pub fn object(&self) -> Option<&str> {
        match self {
            Self::Unknown(object) => object.as_deref(),
            Self::Registered(object) => Some(object),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) enum PendingOperation {
    Directory {
        target: Option<String>,
    },
    Publication {
        sequence: u64,
        receipt: PublicationReceipt,
    },
}

impl PendingOperation {
    pub fn publication(&self) -> Option<u64> {
        match self {
            Self::Directory { .. } => None,
            Self::Publication { sequence, .. } => Some(*sequence),
        }
    }

    pub fn object(&self) -> Option<&str> {
        match self {
            Self::Directory { target } => target.as_deref(),
            Self::Publication { receipt, .. } => receipt.object(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum PendingDocument {
    Retained(AgendaSyncDocument),
    Cleared,
}

/// 未决身份始终保留；正文清理与文件登记是两项独立转换。
#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct StoredPending {
    id: Uuid,
    document: PendingDocument,
    operation: PendingOperation,
}

impl StoredPending {
    pub(super) fn restore(
        id: Uuid,
        document: Option<AgendaSyncDocument>,
        operation: PendingOperation,
    ) -> Self {
        Self {
            id,
            document: document.map_or(PendingDocument::Cleared, PendingDocument::Retained),
            operation,
        }
    }

    pub(super) fn id(&self) -> Uuid {
        self.id
    }

    pub(super) fn document(&self) -> Option<&AgendaSyncDocument> {
        match &self.document {
            PendingDocument::Retained(document) => Some(document),
            PendingDocument::Cleared => None,
        }
    }

    pub(super) fn operation(&self) -> &PendingOperation {
        &self.operation
    }

    pub(super) fn record_receipt(&mut self, value: PublicationReceipt) -> CacheResult<()> {
        let PendingOperation::Publication { receipt, .. } = &mut self.operation else {
            return Err(CacheError::Superseded);
        };
        *receipt = value;
        Ok(())
    }

    /// 目录尝试随本机清除结束；文件发布保留身份，继续阻止分配更高序号。
    pub(crate) fn retain_publication_identity(mut self) -> Option<Self> {
        match self.operation {
            PendingOperation::Directory { .. } => None,
            PendingOperation::Publication { .. } => {
                self.document = PendingDocument::Cleared;
                Some(self)
            }
        }
    }
}
