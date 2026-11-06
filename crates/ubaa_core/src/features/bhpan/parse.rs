use crate::domain::{
    SecretValue,
    bhpan::{BhpanItemKind, BhpanPermission, BhpanSize},
};
use crate::error::{Result, UbaaError};
use serde::Deserialize;

pub(crate) fn invalid() -> UbaaError {
    UbaaError::upstream_changed("北航云盘响应不符合已核实格式")
}
pub(crate) fn json<T: serde::de::DeserializeOwned>(bytes: &[u8]) -> Result<T> {
    serde_json::from_slice(bytes).map_err(|_| invalid())
}

#[derive(Clone)]
pub(crate) struct Item {
    pub id: String,
    pub name: String,
    pub kind: BhpanItemKind,
    pub bytes: Option<u64>,
    pub created: Option<i64>,
    pub modified: Option<i64>,
}
#[derive(Deserialize)]
struct Root {
    id: String,
    name: String,
}
pub(crate) fn roots(bytes: &[u8]) -> Result<Vec<Item>> {
    json::<Vec<Root>>(bytes)?
        .into_iter()
        .map(|r| {
            nonempty(&r.id)?;
            Ok(Item {
                id: r.id,
                name: r.name,
                kind: BhpanItemKind::Folder,
                bytes: None,
                created: None,
                modified: None,
            })
        })
        .collect()
}

#[derive(Deserialize)]
struct WireItem {
    docid: String,
    name: String,
    size: i64,
    modified: i64,
    create_time: Option<i64>,
}
impl WireItem {
    fn item(self, kind: BhpanItemKind) -> Result<Item> {
        nonempty(&self.docid)?;
        let bytes = match (kind, self.size) {
            (BhpanItemKind::Folder, -1) => None,
            (BhpanItemKind::File, value) if value >= 0 => Some(value.cast_unsigned()),
            _ => return Err(invalid()),
        };
        Ok(Item {
            id: self.docid,
            name: self.name,
            kind,
            bytes,
            created: self.create_time.map(|t| t / 1_000_000),
            modified: Some(self.modified / 1_000_000),
        })
    }
}
#[derive(Deserialize)]
struct Directory {
    dirs: Vec<WireItem>,
    files: Vec<WireItem>,
}
pub(crate) fn directory(bytes: &[u8]) -> Result<Vec<Item>> {
    let d: Directory = json(bytes)?;
    d.dirs
        .into_iter()
        .map(|i| i.item(BhpanItemKind::Folder))
        .chain(d.files.into_iter().map(|i| i.item(BhpanItemKind::File)))
        .collect()
}
pub(crate) fn size(bytes: &[u8]) -> Result<BhpanSize> {
    #[derive(Deserialize)]
    struct Size {
        dirnum: u64,
        filenum: u64,
        totalsize: u64,
    }
    let s: Size = json(bytes)?;
    Ok(BhpanSize {
        folders: s.dirnum,
        files: s.filenum,
        bytes: s.totalsize,
    })
}
pub(crate) fn field(bytes: &[u8], name: &str) -> Result<String> {
    let object: serde_json::Value = json(bytes)?;
    let value = object
        .get(name)
        .and_then(serde_json::Value::as_str)
        .ok_or_else(invalid)?;
    nonempty(value)?;
    Ok(value.into())
}
fn nonempty(value: &str) -> Result<()> {
    if value.is_empty() {
        Err(invalid())
    } else {
        Ok(())
    }
}

#[derive(Clone, Deserialize)]
pub(crate) struct ShareItem {
    pub id: Option<String>,
    #[serde(rename = "type")]
    pub kind: Option<String>,
    pub allow: Vec<BhpanPermission>,
}
#[derive(Clone, Deserialize)]
pub(crate) struct Share {
    pub id: String,
    pub title: String,
    pub expires_at: String,
    #[serde(deserialize_with = "secret_string")]
    pub password: SecretValue,
    pub limited_times: i64,
    pub item: ShareItem,
}
fn secret_string<'de, D>(deserializer: D) -> std::result::Result<SecretValue, D::Error>
where
    D: serde::Deserializer<'de>,
{
    String::deserialize(deserializer).map(SecretValue::new)
}
pub(crate) fn share_records(bytes: &[u8]) -> Result<Vec<Share>> {
    let records: Vec<Share> = json(bytes)?;
    for record in &records {
        nonempty(&record.id)?;
    }
    Ok(records)
}
pub(crate) fn share_history(bytes: &[u8]) -> Result<Vec<Share>> {
    #[derive(Deserialize)]
    struct Link {
        id: String,
        title: String,
        allow: Vec<BhpanPermission>,
        expires_at: String,
        password: String,
        limited_times: i64,
    }
    #[derive(Deserialize)]
    struct Document {
        id: String,
        #[serde(rename = "type")]
        kind: String,
    }
    #[derive(Deserialize)]
    struct Entry {
        doc: Document,
        link_configs: Vec<Link>,
    }
    #[derive(Deserialize)]
    struct History {
        entries: Vec<Entry>,
    }
    let h: History = json(bytes)?;
    let mut result = Vec::new();
    for entry in h.entries {
        nonempty(&entry.doc.id)?;
        if !matches!(entry.doc.kind.as_str(), "file" | "folder") {
            return Err(invalid());
        }
        for link in entry.link_configs {
            nonempty(&link.id)?;
            result.push(Share {
                id: link.id,
                title: link.title,
                expires_at: link.expires_at,
                password: SecretValue::new(link.password),
                limited_times: link.limited_times,
                item: ShareItem {
                    id: Some(entry.doc.id.clone()),
                    kind: Some(entry.doc.kind.clone()),
                    allow: link.allow,
                },
            });
        }
    }
    Ok(result)
}

pub(crate) fn received_share(bytes: &[u8]) -> Result<Item> {
    #[derive(Deserialize)]
    struct Received {
        created_at: String,
        modified_at: String,
        id: String,
        name: String,
        size: Option<u64>,
    }
    let [item]: [Received; 1] = json(bytes)?;
    nonempty(&item.id)?;
    let date = |v: &str| {
        chrono::DateTime::parse_from_rfc3339(v)
            .map(|t| t.timestamp())
            .map_err(|_| invalid())
    };
    Ok(Item {
        id: item.id,
        name: item.name,
        kind: if item.size.is_some() {
            BhpanItemKind::File
        } else {
            BhpanItemKind::Folder
        },
        bytes: item.size,
        created: Some(date(&item.created_at)?),
        modified: Some(date(&item.modified_at)?),
    })
}
