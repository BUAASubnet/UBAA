//! 旁车文件按范围合并，独立于主会话锁和修订号。
use super::super::file_safety::{
    create_temporary_file, open_existing_session_file, prevent_symlink_following,
    restrict_directory, restrict_file_creation, restrict_open_file, session_error, sync_directory,
    validate_directory, validate_open_regular_file, validate_regular_file,
};
use super::super::file_store::{try_file_lock, wait_for_lock};
use super::super::storage::TemporaryFile;
use super::{BusinessMaterial, BusinessScope, ClearNonce, ContentVersion};
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
const SCHEMA: u32 = 2;

#[derive(Deserialize, Serialize)]
pub(super) struct Document {
    schema: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) account: Option<String>,
    #[serde(default, skip_serializing_if = "Routes::is_empty")]
    routes: Routes,
    #[serde(default, skip_serializing_if = "ClearNonces::is_empty")]
    clear_nonces: ClearNonces,
    #[serde(default)]
    content_versions: ContentVersions,
}

#[derive(Default, Deserialize, Serialize)]
struct Routes {
    direct: BTreeMap<BusinessScope, Entry>,
    webvpn: BTreeMap<BusinessScope, Entry>,
}

impl Routes {
    fn is_empty(&self) -> bool {
        self.direct.is_empty() && self.webvpn.is_empty()
    }
}

#[derive(Default, Deserialize, Serialize)]
struct ClearNonces {
    direct: Option<ClearNonce>,
    webvpn: Option<ClearNonce>,
}

impl ClearNonces {
    fn is_empty(&self) -> bool {
        self.direct.is_none() && self.webvpn.is_none()
    }
}

#[derive(Deserialize, Serialize)]
struct ContentVersions {
    #[serde(default = "rand::random")]
    direct: ContentVersion,
    #[serde(default = "rand::random")]
    webvpn: ContentVersion,
}

impl Default for ContentVersions {
    fn default() -> Self {
        Self {
            direct: rand::random(),
            webvpn: rand::random(),
        }
    }
}

#[derive(Deserialize, Serialize)]
pub(super) struct Entry {
    pub(super) saved_at: i64,
    pub(super) material: BusinessMaterial,
}

impl Default for Document {
    fn default() -> Self {
        Self {
            schema: SCHEMA,
            account: None,
            routes: Routes::default(),
            clear_nonces: ClearNonces::default(),
            content_versions: ContentVersions::default(),
        }
    }
}

impl Document {
    pub(super) fn nonce(&self, route: ConnectionMode) -> Option<ClearNonce> {
        match route {
            ConnectionMode::Direct => self.clear_nonces.direct,
            ConnectionMode::WebVpn => self.clear_nonces.webvpn,
        }
    }

    fn advance_nonce(&mut self, route: ConnectionMode) {
        let slot = match route {
            ConnectionMode::Direct => &mut self.clear_nonces.direct,
            ConnectionMode::WebVpn => &mut self.clear_nonces.webvpn,
        };
        *slot = Some(rand::random());
    }

    pub(super) fn content_version(&self, route: ConnectionMode) -> ContentVersion {
        match route {
            ConnectionMode::Direct => self.content_versions.direct,
            ConnectionMode::WebVpn => self.content_versions.webvpn,
        }
    }

    fn advance_content_version(&mut self, route: ConnectionMode) {
        let slot = match route {
            ConnectionMode::Direct => &mut self.content_versions.direct,
            ConnectionMode::WebVpn => &mut self.content_versions.webvpn,
        };
        *slot = rand::random();
    }

    fn clear_route(&mut self, route: ConnectionMode) {
        self.route(route).clear();
        if self.routes.is_empty() {
            self.account = None;
        }
        self.advance_nonce(route);
        self.advance_content_version(route);
    }

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
        nonce: Option<ClearNonce>,
        changes: &[(BusinessScope, Option<BusinessMaterial>)],
        saved_at: i64,
        current: impl FnOnce() -> bool,
    ) -> Result<()> {
        let _lock = self.lock()?;
        let mut document = self.read()?.unwrap_or_default();
        if document.nonce(route) != nonce {
            return Ok(());
        }
        if document.account.as_deref() != Some(account) {
            document.routes = Routes::default();
            document.content_versions = ContentVersions::default();
            document.account = Some(account.to_owned());
        }
        let now = chrono::Utc::now().timestamp();
        for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
            let entries = document.route(mode);
            let before = entries.len();
            entries.retain(|_, entry| entry.saved_at <= now);
            if entries.len() != before {
                document.advance_content_version(mode);
            }
        }
        let entries = document.route(route);
        for (scope, material) in changes {
            if let Some(material) = material {
                entries.insert(
                    *scope,
                    Entry {
                        saved_at,
                        material: material.clone(),
                    },
                );
            } else {
                entries.remove(scope);
            }
        }
        document.advance_content_version(route);
        self.replace(&document, current)
    }

    pub(super) fn reject(
        &self,
        account: &str,
        route: ConnectionMode,
        nonce: Option<ClearNonce>,
        scope: BusinessScope,
        rejected: &BusinessMaterial,
        current: impl Fn() -> bool,
    ) -> Result<()> {
        let _lock = self.lock()?;
        if !current() {
            return Ok(());
        }
        if let Some(mut document) = self.read()?.filter(|document| {
            document.account.as_deref() == Some(account) && document.nonce(route) == nonce
        }) {
            let entries = document.route(route);
            if entries
                .get(&scope)
                .is_some_and(|entry| entry.material.matches(rejected))
            {
                entries.remove(&scope);
                if document.routes.is_empty() {
                    document.account = None;
                }
                document.advance_content_version(route);
                self.replace(&document, current)?;
            }
        }
        Ok(())
    }

    pub(super) fn clear_route(&self, route: ConnectionMode) -> Result<()> {
        let _lock = self.lock()?;
        let mut document = self.read()?.unwrap_or_default();
        document.clear_route(route);
        self.replace(&document, || true)
    }

    pub(super) fn clear(&self) -> Result<()> {
        let _lock = self.lock()?;
        let mut document = Document::default();
        document.advance_nonce(ConnectionMode::Direct);
        document.advance_nonce(ConnectionMode::WebVpn);
        self.replace(&document, || true)
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

    fn replace(&self, document: &Document, current: impl FnOnce() -> bool) -> Result<()> {
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
        if !current() {
            return Ok(());
        }
        fs::rename(cleanup.path(), &self.path)
            .map_err(|_| session_error("业务会话缓存替换失败"))?;
        cleanup.persisted();
        sync_directory(&self.directory)
    }
}
