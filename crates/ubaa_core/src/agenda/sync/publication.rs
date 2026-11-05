use super::{
    AgendaSyncDocument, AgendaSyncSnapshot,
    document::{DOCUMENT_LIMIT, encode_value},
};
use crate::cache::{CacheError, CacheResult};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// 文件发布身份只选择同设备的最新快照，不参与记录版本比较。
#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub(crate) struct Publication {
    pub publisher: Uuid,
    pub sequence: u64,
}
#[derive(Deserialize, Serialize)]
struct PublishedDocument {
    publisher: Uuid,
    publication: u64,
    #[serde(flatten)]
    document: AgendaSyncDocument,
}
impl Publication {
    pub fn file_name(self) -> String {
        format!("p_{}_{:020}.json", self.publisher.simple(), self.sequence)
    }
    pub fn parse_file_name(name: &str) -> CacheResult<Self> {
        let (publisher, sequence) = name
            .strip_prefix("p_")
            .and_then(|v| v.strip_suffix(".json"))
            .and_then(|v| v.split_once('_'))
            .ok_or(CacheError::Corrupt)?;
        let value = Self {
            publisher: Uuid::parse_str(publisher).map_err(|_| CacheError::Corrupt)?,
            sequence: sequence.parse().map_err(|_| CacheError::Corrupt)?,
        };
        value.valid()?;
        if value.file_name() != name {
            return Err(CacheError::Corrupt);
        }
        Ok(value)
    }
    fn valid(self) -> CacheResult<()> {
        if self.publisher.is_nil() || self.sequence == 0 || self.sequence > i64::MAX as u64 {
            return Err(CacheError::Corrupt);
        }
        Ok(())
    }
    pub fn encode(self, document: &AgendaSyncDocument) -> CacheResult<Vec<u8>> {
        self.valid()?;
        encode_value(&PublishedDocument {
            publisher: self.publisher,
            publication: self.sequence,
            document: document.normalized()?,
        })
    }
    pub fn decode(self, bytes: &[u8]) -> CacheResult<AgendaSyncDocument> {
        self.valid()?;
        if bytes.len() > DOCUMENT_LIMIT {
            return Err(CacheError::Capacity);
        }
        let value: PublishedDocument =
            serde_json::from_slice(bytes).map_err(|_| CacheError::Corrupt)?;
        if value.publisher != self.publisher || value.publication != self.sequence {
            return Err(CacheError::Corrupt);
        }
        value.document.normalized()
    }
    pub fn from_snapshot(snapshot: &AgendaSyncSnapshot) -> CacheResult<Self> {
        let value = Self {
            publisher: snapshot.device_id,
            sequence: snapshot.publication.ok_or(CacheError::Superseded)?,
        };
        value.valid()?;
        Ok(value)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn file_and_body_bind_exactly_one_publication() {
        let identity = Publication {
            publisher: Uuid::new_v4(),
            sequence: 7,
        };
        let name = identity.file_name();
        assert_eq!(Publication::parse_file_name(&name).unwrap(), identity);
        let body = identity.encode(&AgendaSyncDocument::default()).unwrap();
        assert_eq!(
            identity.decode(&body).unwrap(),
            AgendaSyncDocument::default()
        );
        assert!(
            Publication {
                sequence: 8,
                ..identity
            }
            .decode(&body)
            .is_err()
        );
        assert!(
            Publication {
                publisher: Uuid::new_v4(),
                ..identity
            }
            .decode(&body)
            .is_err()
        );
        assert!(Publication::parse_file_name(&name.replace("00000000000000000007", "7")).is_err());
        assert!(
            Publication::parse_file_name(
                "p_00000000000000000000000000000000_00000000000000000001.json"
            )
            .is_err()
        );
    }
}
