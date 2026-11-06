use super::{EFAST, HttpMethod, Result, UbaaClient, UbaaError, parse, wire};
use crate::domain::bhpan::{BhpanItem, BhpanItemKind, BhpanPathLookup};
use serde::Deserialize;
use std::collections::{HashMap, HashSet};

#[derive(Clone, Deserialize, Eq, PartialEq)]
struct Entry {
    id: String,
    name: String,
    rev: String,
    size: i64,
    created_at: String,
    modified_at: String,
}
impl Entry {
    fn item(&self, kind: BhpanItemKind) -> Result<parse::Item> {
        if self.id.is_empty() || self.name.is_empty() || self.rev.is_empty() {
            return Err(parse::invalid());
        }
        let bytes = match (kind, self.size) {
            (BhpanItemKind::Folder, -1) => None,
            (BhpanItemKind::File, size) if size >= 0 => Some(size.cast_unsigned()),
            _ => return Err(parse::invalid()),
        };
        let timestamp = |value: &str| {
            chrono::DateTime::parse_from_rfc3339(value)
                .map(|time| time.timestamp())
                .map_err(|_| parse::invalid())
        };
        Ok(parse::Item {
            id: self.id.clone(),
            name: self.name.clone(),
            kind,
            bytes,
            created: Some(timestamp(&self.created_at)?),
            modified: Some(timestamp(&self.modified_at)?),
        })
    }
}
#[derive(Deserialize)]
struct Page {
    dirs: Vec<Entry>,
    files: Vec<Entry>,
    next_marker: String,
}

impl UbaaClient {
    /// 使用完整分页逐层定位个人路径，缺失仅在全部分页结束后确定。
    /// # Errors
    /// 名称非法、路径歧义、非目录或任一页失败时拒绝。
    pub async fn bhpan_lookup_personal_path_complete(
        &mut self,
        components: &[String],
    ) -> Result<BhpanPathLookup> {
        for name in components {
            super::write::name(name)?;
        }
        let mut current = self
            .bhpan_personal_root()
            .await?
            .items
            .into_iter()
            .next()
            .ok_or_else(parse::invalid)?;
        for (index, name) in components.iter().enumerate() {
            let items = self.bhpan_list_complete(&current.handle).await?;
            let mut matched = items.into_iter().filter(|item| item.name == *name);
            let next = matched.next();
            if matched.next().is_some() {
                return Err(UbaaError::invalid_input("个人路径存在同名歧义"));
            }
            let Some(next) = next else {
                return Ok(BhpanPathLookup::Missing {
                    parent: current,
                    remaining: components[index..].to_vec(),
                });
            };
            current = next;
        }
        Ok(BhpanPathLookup::Found(current))
    }
    /// 只列举已签发的个人目录，全部分页结束后才交付条目。
    /// # Errors
    /// 标记重复、条目冲突、字段缺失或任一页失败时不返回部分目录。
    pub async fn bhpan_list_complete(&mut self, parent: &str) -> Result<Vec<BhpanItem>> {
        self.bhpan_scope()?;
        let authority = self.bhpan.item(parent)?;
        authority.personal()?;
        authority.folder()?;
        let token = self.bhpan_ready().await?;
        let path = format!(
            "{EFAST}/folders/{}/sub_objects?limit=1000",
            wire::segment(&authority.item.id)
        );
        let mut marker = None;
        let mut markers = HashSet::new();
        let mut known = HashMap::<String, (Entry, BhpanItemKind)>::new();
        let mut items = Vec::new();
        loop {
            self.bhpan_scope()?;
            let path = marker.as_ref().map_or_else(
                || path.clone(),
                |marker: &String| format!("{path}&marker={}", wire::segment(marker)),
            );
            let bytes = wire::api(
                &mut self.direct_runtime,
                &token,
                HttpMethod::Get,
                &path,
                None,
                None,
                false,
            )
            .await?;
            self.guard_latest_session_ownership()?;
            let page: Page = parse::json(&bytes)?;
            for (entries, kind) in [
                (page.dirs, BhpanItemKind::Folder),
                (page.files, BhpanItemKind::File),
            ] {
                for entry in entries {
                    let item = entry.item(kind)?;
                    if let Some(previous) = known.get(&entry.id) {
                        if previous != &(entry, kind) {
                            return Err(parse::invalid());
                        }
                    } else {
                        known.insert(entry.id.clone(), (entry, kind));
                        items.push(item);
                    }
                }
            }
            if page.next_marker.is_empty() {
                break;
            }
            if !markers.insert(page.next_marker.clone()) {
                return Err(parse::invalid());
            }
            marker = Some(page.next_marker);
        }
        Ok(self
            .bhpan_page(
                items,
                authority.scope,
                authority.root_kind,
                Some(&authority.root_id),
                None,
                "",
            )?
            .items)
    }
}
