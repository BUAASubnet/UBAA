//! 本机账号登记与日程访问共用配置作用域排他锁，锁持有至结果交付结束。
mod material;
mod paths;
mod read;
#[cfg(all(test, unix))]
#[path = "../../../../apps/ubaa_cli/tests/agenda_read/internal.rs"]
mod tests;

use fs2::FileExt;
#[doc(hidden)]
pub use material::keychain_worker;
use material::{Material, PlatformMaterial};
use paths::Paths;
pub use read::run_agenda;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;
use ubaa_core::facade::{AgendaStore, CacheError, UbaaClient, VerifiedLoginIdentity};
use uuid::Uuid;

type LocalResult<T> = Result<T, LocalError>;
/// 只暴露稳定错误类别，不携带路径、身份和原生安全存储诊断。
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LocalError {
    RegistrationRequired,
    MaterialUnavailable,
    MaterialCorrupt,
    Storage,
    StaleIdentity,
    CacheKeyMissing,
    CacheMissing,
    CacheCorrupt,
    AgendaCorrupt,
    InvalidInput,
    NotFound,
}
impl LocalError {
    pub(crate) const fn message(self) -> &'static str {
        match self {
            Self::RegistrationRequired => "本机日程尚未登记活动账号，请先显式登录",
            Self::MaterialUnavailable => "本机账号安全材料不可用",
            Self::MaterialCorrupt => "本机账号安全材料缺失或损坏，已保留原文件",
            Self::Storage => "本机私有目录或存储不可用",
            Self::StaleIdentity => "本机账号身份能力已失效",
            Self::CacheKeyMissing => "学校缓存密钥缺失，本机日程仍可独立读取",
            Self::CacheMissing => "CLI 尚无可用学校缓存",
            Self::CacheCorrupt => "学校缓存无法校验，已停止合并",
            Self::AgendaCorrupt => "本机日程无法读取，已保留原文件",
            Self::InvalidInput => "本机日程参数无效",
            Self::NotFound => "本机日程事项不存在",
        }
    }
    pub(crate) const fn exit(self) -> i32 {
        match self {
            Self::InvalidInput => 2,
            Self::RegistrationRequired | Self::StaleIdentity => 3,
            _ => 7,
        }
    }
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Account {
    alias: String,
    cache_key: Option<Vec<u8>>,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Index {
    version: u32,
    anchor: String,
    directory: String,
    accounts: BTreeMap<String, Account>,
    active: Option<String>,
    epoch: String,
}
/// 配置作用域锁的拥有者。不能从账号、别名或普通资料构造活动身份。
pub struct AgendaAccess {
    paths: Paths,
    scope: String,
    material: Box<dyn Material>,
}
impl AgendaAccess {
    /// 打开生产作用域，不读取学校会话或 Flutter 材料。
    ///
    /// # Errors
    /// 路径不安全、平台能力或锁不可用时失败。
    pub fn open(root: &Path) -> LocalResult<Self> {
        Self::with_material(root, Box::new(PlatformMaterial))
    }
    fn with_material(root: &Path, material: Box<dyn Material>) -> LocalResult<Self> {
        let paths = Paths::open(root)?;
        FileExt::lock_exclusive(&paths.lock).map_err(|_| LocalError::Storage)?;
        paths.validate()?;
        let scope = format!(
            "{:x}",
            Sha256::digest(paths.root.as_os_str().as_encoded_bytes())
        );
        Ok(Self {
            paths,
            scope,
            material,
        })
    }
    /// 与作用域锁一致的规范化配置目录。
    #[must_use]
    pub fn config_dir(&self) -> &Path {
        &self.paths.root
    }
    fn anchor(&self) -> LocalResult<String> {
        let mut data = String::new();
        let mut file = self
            .paths
            .lock
            .try_clone()
            .map_err(|_| LocalError::Storage)?;
        file.seek(SeekFrom::Start(0))
            .map_err(|_| LocalError::Storage)?;
        file.take(129)
            .read_to_string(&mut data)
            .map_err(|_| LocalError::Storage)?;
        Ok(data)
    }
    fn load(&self) -> LocalResult<Option<Index>> {
        self.paths.validate()?;
        if self
            .paths
            .root
            .join("cli-accounts.pending")
            .symlink_metadata()
            .is_ok()
        {
            return Err(LocalError::MaterialCorrupt);
        }
        let anchor = self.anchor()?;
        let data = self.material.read(&self.scope)?;
        match (anchor.is_empty(), data) {
            (true, None) => {
                // 首次初始化不能认领已有日程或业务缓存。
                if self.paths.root.join("agenda").exists()
                    || self.paths.root.join("business-cache").exists()
                {
                    return Err(LocalError::MaterialCorrupt);
                }
                Ok(None)
            }
            (false, Some(data)) => {
                let index: Index =
                    serde_json::from_slice(&data).map_err(|_| LocalError::MaterialCorrupt)?;
                if index.version != 1
                    || index.anchor != anchor
                    || index.directory != self.paths.identity()?
                    || !valid_alias(&index.anchor)
                    || !valid_alias(&index.epoch)
                    || index
                        .active
                        .as_ref()
                        .is_some_and(|id| !index.accounts.contains_key(id))
                    || index.accounts.iter().any(|(id, a)| {
                        id.is_empty()
                            || id.len() > 128
                            || !valid_alias(&a.alias)
                            || a.cache_key.as_ref().is_some_and(|key| key.len() != 32)
                    })
                    || index
                        .accounts
                        .values()
                        .map(|a| &a.alias)
                        .collect::<std::collections::BTreeSet<_>>()
                        .len()
                        != index.accounts.len()
                {
                    return Err(LocalError::MaterialCorrupt);
                }
                Ok(Some(index))
            }
            _ => Err(LocalError::MaterialCorrupt),
        }
    }
    fn check_index(&self, index: &Index) -> LocalResult<()> {
        self.material
            .check_write(&serde_json::to_vec(index).map_err(|_| LocalError::MaterialCorrupt)?)
    }
    fn save(&self, index: &Index) -> LocalResult<()> {
        self.paths.validate()?;
        let data = serde_json::to_vec(index).map_err(|_| LocalError::MaterialCorrupt)?;
        self.material.check_write(&data)?;
        self.material.write(&self.scope, &data)?;
        // 写后核对，不能将不可确认的持久化称为激活成功。
        if self.material.read(&self.scope)?.as_deref() != Some(data.as_slice()) {
            return Err(LocalError::MaterialUnavailable);
        }
        self.paths.validate()
    }
    fn initialize(&self) -> LocalResult<Index> {
        if let Some(index) = self.load()? {
            return Ok(index);
        }
        let index = Index {
            version: 1,
            anchor: random(),
            directory: self.paths.identity()?,
            accounts: BTreeMap::new(),
            active: None,
            epoch: random(),
        };
        // 先持久写入不可覆盖的初始化标记；中途崩溃会保留非空标记并失败关闭。
        let mut file = self
            .paths
            .lock
            .try_clone()
            .map_err(|_| LocalError::Storage)?;
        file.seek(SeekFrom::Start(0))
            .map_err(|_| LocalError::Storage)?;
        file.write_all(index.anchor.as_bytes())
            .and_then(|()| file.sync_all())
            .map_err(|_| LocalError::Storage)?;
        File::open(&self.paths.root)
            .and_then(|f| f.sync_all())
            .map_err(|_| LocalError::Storage)?;
        self.save(&index)?;
        Ok(index)
    }
    /// 显式登录、诊断登录或退出前撤销当前选择。材料和日程保留。
    ///
    /// # Errors
    /// 持久化撤销失败或日程不能关闭时失败，不继续认证和切号。
    pub fn revoke(&mut self) -> LocalResult<()> {
        if !self.material.supported() {
            self.paths.validate()?;
            if !self.anchor()?.is_empty() {
                return Err(LocalError::MaterialUnavailable);
            }
            for name in ["cli-accounts.pending", "agenda", "business-cache"] {
                match self.paths.root.join(name).symlink_metadata() {
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
                    _ => return Err(LocalError::MaterialUnavailable),
                }
            }
            return Ok(());
        }
        let Some(mut index) = self.load()? else {
            return Ok(());
        };
        let old = index.active.take();
        index.epoch = random();
        self.check_index(&index)?;
        self.begin_transition()?;
        self.save(&index)?;
        if let Some(id) = old {
            self.agenda(&index.accounts[&id])?
                .deactivate()
                .map_err(agenda_error)?;
        }
        self.finish_transition()
    }
    /// 只接收当前 Core 显式成功登录能力；调用时仍持有同一作用域跨进程锁。
    ///
    /// # Errors
    /// 能力失效、索引不完整、目录变动或任意持久化失败时拒绝激活。
    pub fn register(
        &mut self,
        client: &mut UbaaClient,
        identity: &VerifiedLoginIdentity,
    ) -> LocalResult<()> {
        if !self.material.supported() {
            return Err(LocalError::MaterialUnavailable);
        }
        let id = client
            .validate_login_identity(identity)
            .map_err(|_| LocalError::StaleIdentity)?
            .to_owned();
        let mut index = self.initialize()?;
        if index.active.is_some() {
            return Err(LocalError::StaleIdentity);
        }
        index.accounts.entry(id.clone()).or_insert_with(|| Account {
            alias: random(),
            cache_key: None,
        });
        index.epoch = random();
        self.check_index(&index)?;
        index.active = Some(id.clone());
        self.check_index(&index)?;
        index.active = None;
        self.begin_transition()?;
        // 先持久保存稳定映射和 inactive 状态，避免日程创建后映射写失败。
        self.save(&index)?;
        let store = self.agenda(&index.accounts[&id])?;
        store.activate().map_err(agenda_error)?;
        client
            .validate_login_identity(identity)
            .map_err(|_| LocalError::StaleIdentity)?;
        index.active = Some(id);
        self.save(&index)?;
        client
            .consume_login_identity(identity)
            .map_err(|_| LocalError::StaleIdentity)?;
        self.finish_transition()
    }
    fn begin_transition(&self) -> LocalResult<()> {
        self.paths.validate()?;
        let mut options = std::fs::OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600).custom_flags(libc::O_NOFOLLOW);
        }
        options
            .open(self.paths.root.join("cli-accounts.pending"))
            .and_then(|f| f.sync_all())
            .map_err(|_| LocalError::Storage)?;
        File::open(&self.paths.root)
            .and_then(|f| f.sync_all())
            .map_err(|_| LocalError::Storage)
    }
    fn finish_transition(&self) -> LocalResult<()> {
        self.paths.validate()?;
        paths::private(&self.paths.root.join("cli-accounts.pending"), false)?;
        std::fs::remove_file(self.paths.root.join("cli-accounts.pending"))
            .map_err(|_| LocalError::Storage)?;
        File::open(&self.paths.root)
            .and_then(|f| f.sync_all())
            .map_err(|_| LocalError::Storage)
    }
    fn agenda(&self, account: &Account) -> LocalResult<AgendaStore> {
        AgendaStore::open(&self.paths.root, &account.alias).map_err(agenda_error)
    }
    fn active(&self) -> LocalResult<Index> {
        let index = self.load()?.ok_or(LocalError::RegistrationRequired)?;
        if index.active.is_none() {
            return Err(LocalError::RegistrationRequired);
        }
        Ok(index)
    }
}
fn random() -> String {
    Uuid::new_v4().simple().to_string()
}
fn valid_alias(value: &str) -> bool {
    value.len() == 32 && value.bytes().all(|c| c.is_ascii_hexdigit())
}
fn agenda_error(error: CacheError) -> LocalError {
    match error {
        CacheError::InvalidInput | CacheError::Capacity => LocalError::InvalidInput,
        CacheError::Inactive | CacheError::Superseded => LocalError::StaleIdentity,
        _ => LocalError::AgendaCorrupt,
    }
}
