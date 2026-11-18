//! 旁车文件按范围合并，独立于主会话锁和修订号。
use super::super::file_safety::{
    create_temporary_file, open_existing_session_file, prevent_symlink_following,
    restrict_directory, restrict_file_creation, restrict_open_file, session_error, sync_directory,
    validate_directory, validate_open_regular_file, validate_regular_file,
};
use super::super::file_store::{try_file_lock, wait_for_lock};
use super::super::storage::TemporaryFile;
use super::{BusinessScope, StoredCookie, same_material};
use crate::domain::ConnectionMode;
use crate::error::Result;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

const FILE: &str = "business_session.json";
const LOCK: &str = ".business_session.lock";
const MAX_BYTES: u64 = 256 * 1024;
const SCHEMA: u32 = 1;

#[derive(Deserialize, Serialize)]
pub(super) struct Document {
    schema: u32,
    pub(super) account: String,
    routes: Routes,
}

#[derive(Default, Deserialize, Serialize)]
struct Routes {
    direct: BTreeMap<BusinessScope, Entry>,
    webvpn: BTreeMap<BusinessScope, Entry>,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Entry {
    saved_at: i64,
    pub(super) material: Material,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
pub(super) enum Material {
    Cookies(Vec<StoredCookie>),
}

impl Document {
    pub(super) fn route(&mut self, route: ConnectionMode) -> &mut BTreeMap<BusinessScope, Entry> {
        match route {
            ConnectionMode::Direct => &mut self.routes.direct,
            ConnectionMode::WebVpn => &mut self.routes.webvpn,
        }
    }
}

pub(super) struct BusinessSessionFile {
    directory: PathBuf,
    path: PathBuf,
}

impl BusinessSessionFile {
    pub(super) fn new(directory: &Path) -> Self {
        Self {
            directory: directory.to_owned(),
            path: directory.join(FILE),
        }
    }

    pub(super) fn read(&self) -> Result<Option<Document>> {
        validate_directory(&self.directory)?;
        if !validate_regular_file(&self.path, "业务会话缓存要求普通文件")? {
            return Ok(None);
        }
        let Some(file) = open_existing_session_file(&self.path)? else {
            return Ok(None);
        };
        restrict_open_file(&file, "业务会话缓存文件权限不可用")?;
        let mut contents = Vec::new();
        file.take(MAX_BYTES + 1)
            .read_to_end(&mut contents)
            .map_err(|_| session_error("业务会话缓存读取失败"))?;
        if contents.len() as u64 > MAX_BYTES {
            return Ok(None);
        }
        Ok(serde_json::from_slice::<Document>(&contents)
            .ok()
            .filter(|document| document.schema == SCHEMA))
    }

    pub(super) fn write(
        &self,
        account: &str,
        route: ConnectionMode,
        changes: &[(BusinessScope, Vec<StoredCookie>)],
        saved_at: i64,
        current: impl FnOnce() -> bool,
    ) -> Result<()> {
        let _lock = self.lock()?;
        if !current() {
            return Ok(());
        }
        let mut document = self
            .read()?
            .filter(|document| document.account == account)
            .unwrap_or_else(|| Document {
                schema: SCHEMA,
                account: account.to_owned(),
                routes: Routes::default(),
            });
        let entries = document.route(route);
        for (scope, cookies) in changes {
            if cookies.is_empty() {
                entries.remove(scope);
            } else {
                entries.insert(
                    *scope,
                    Entry {
                        saved_at,
                        material: Material::Cookies(cookies.clone()),
                    },
                );
            }
        }
        self.replace(&document)
    }

    pub(super) fn reject(
        &self,
        account: &str,
        route: ConnectionMode,
        scope: BusinessScope,
        rejected: &[StoredCookie],
    ) -> Result<()> {
        let _lock = self.lock()?;
        if let Some(mut document) = self.read()?.filter(|document| document.account == account) {
            let entries = document.route(route);
            if entries.get(&scope).is_some_and(|entry| {
                let Material::Cookies(cookies) = &entry.material;
                same_material(cookies, rejected)
            }) {
                entries.remove(&scope);
                self.replace(&document)?;
            }
        }
        Ok(())
    }

    pub(super) fn clear_login(&self, account: Option<&str>, route: ConnectionMode) -> Result<()> {
        if !validate_regular_file(&self.path, "业务会话缓存要求普通文件")? {
            return Ok(());
        }
        let _lock = self.lock()?;
        if let Some(mut document) = self
            .read()?
            .filter(|document| Some(document.account.as_str()) == account)
        {
            let entries = document.route(route);
            if !entries.is_empty() {
                entries.clear();
                self.replace(&document)?;
            }
            return Ok(());
        }
        self.remove()
    }

    pub(super) fn clear(&self) -> Result<()> {
        if !validate_regular_file(&self.path, "业务会话缓存要求普通文件")? {
            return Ok(());
        }
        let _lock = self.lock()?;
        self.remove()
    }

    fn remove(&self) -> Result<()> {
        if validate_regular_file(&self.path, "业务会话缓存要求普通文件")? {
            fs::remove_file(&self.path).map_err(|_| session_error("业务会话缓存清理失败"))?;
            sync_directory(&self.directory)?;
        }
        Ok(())
    }

    fn lock(&self) -> Result<File> {
        validate_directory(&self.directory)?;
        restrict_directory(&self.directory)?;
        let path = self.directory.join(LOCK);
        validate_regular_file(&path, "业务会话缓存锁要求普通文件")?;
        let mut options = OpenOptions::new();
        options.read(true).write(true).create(true);
        restrict_file_creation(&mut options);
        prevent_symlink_following(&mut options);
        let file = options
            .open(path)
            .map_err(|_| session_error("业务会话缓存锁不可用"))?;
        validate_open_regular_file(&file, "业务会话缓存锁要求普通文件", "业务会话缓存锁不可用")?;
        restrict_open_file(&file, "业务会话缓存锁权限不可用")?;
        let deadline = Instant::now() + Duration::from_secs(2);
        while !try_file_lock(&file)? {
            wait_for_lock(deadline)?;
        }
        Ok(file)
    }

    fn replace(&self, document: &Document) -> Result<()> {
        let contents =
            serde_json::to_vec(document).map_err(|_| session_error("业务会话缓存编码失败"))?;
        if contents.len() as u64 > MAX_BYTES {
            return Err(session_error("业务会话缓存超过大小限制"));
        }
        let (temporary, mut file) = create_temporary_file(&self.directory, FILE)?;
        let mut cleanup = TemporaryFile::new(temporary);
        restrict_open_file(&file, "业务会话缓存文件权限不可用")?;
        file.write_all(&contents)
            .and_then(|()| file.sync_all())
            .map_err(|_| session_error("业务会话缓存写入失败"))?;
        drop(file);
        validate_regular_file(&self.path, "业务会话缓存要求普通文件")?;
        fs::rename(cleanup.path(), &self.path)
            .map_err(|_| session_error("业务会话缓存替换失败"))?;
        cleanup.persisted();
        sync_directory(&self.directory)
    }
}
