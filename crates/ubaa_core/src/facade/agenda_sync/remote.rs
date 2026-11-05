use super::{
    Binding,
    scratch::{self, Scratch},
};
use crate::{
    agenda::sync::{
        coordinator::{BeforeCommit, RemoteCommit, RemoteError, RemoteLocation, SyncRemote},
        publication::Publication,
    },
    domain::bhpan::{
        BhpanFileVersion, BhpanItemKind, BhpanPathLookup, BhpanVersionUploadOutcome,
        BhpanWriteIntent,
    },
    facade::{UbaaClient, bhpan::BhpanTransfer},
};
use async_trait::async_trait;
use std::path::{Path, PathBuf};

const COMPONENTS: [&str; 2] = ["UBAA", "agenda_snapshots"];
pub(super) struct BhpanRemote<'a> {
    client: &'a mut UbaaClient,
    binding: Binding,
    scratch_root: &'a Path,
    creation: Option<(String, Vec<String>)>,
    folder: Option<String>,
}
impl<'a> BhpanRemote<'a> {
    pub(super) fn new(
        client: &'a mut UbaaClient,
        binding: Binding,
        scratch_root: &'a Path,
    ) -> Self {
        Self {
            client,
            binding,
            scratch_root,
            creation: None,
            folder: None,
        }
    }
    async fn upload(
        &mut self,
        identity: Publication,
        path: PathBuf,
        before_commit: BeforeCommit<'_>,
    ) -> Result<RemoteCommit<BhpanFileVersion>, RemoteError> {
        let folder = self.folder.as_ref().ok_or(RemoteError::Failed)?;
        let prepared = self
            .client
            .bhpan_prepare_upload(folder, path, &identity.file_name(), BhpanTransfer::new())
            .await
            .map_err(RemoteError::Core)?;
        self.check_current()?;
        before_commit()?;
        let outcome = self
            .client
            .bhpan_commit_upload_version(&prepared.handle)
            .await
            .map_err(RemoteError::Core)?;
        self.check_current()?;
        Ok(match outcome {
            BhpanVersionUploadOutcome::Committed { version } => RemoteCommit::Committed(version),
            BhpanVersionUploadOutcome::OutcomeUnknown { version } => {
                RemoteCommit::OutcomeUnknown(version)
            }
        })
    }
}
#[async_trait]
impl SyncRemote for BhpanRemote<'_> {
    type Version = BhpanFileVersion;
    fn check_current(&self) -> Result<(), RemoteError> {
        self.client
            .direct_runtime
            .ensure_primary_client()
            .map_err(RemoteError::Core)?;
        if Binding::capture(self.client) != self.binding {
            return Err(RemoteError::Superseded);
        }
        let capabilities = self.client.bhpan_capabilities();
        if capabilities.direct_metadata != crate::domain::bhpan::BhpanCapability::Available
            || capabilities.object_transfer != crate::domain::bhpan::BhpanCapability::Available
        {
            return Err(RemoteError::Unverified);
        }
        Ok(())
    }
    fn publication(&self, version: &Self::Version) -> Publication {
        Publication::parse_file_name(&version.name).expect("目录与上传均已核对快照文件名")
    }
    fn same_version(&self, left: &Self::Version, right: &Self::Version) -> bool {
        self.object_key(left) == self.object_key(right)
    }
    fn object_key(&self, version: &Self::Version) -> String {
        serde_json::to_string(&(&version.docid, &version.rev, &version.name, version.bytes))
            .expect("字符串与字节数可序列化")
    }
    async fn locate(&mut self) -> Result<RemoteLocation<Vec<Self::Version>>, RemoteError> {
        self.folder = None;
        self.creation = None;
        let result = self
            .client
            .bhpan_lookup_personal_path_complete(&COMPONENTS.map(str::to_owned))
            .await
            .map_err(RemoteError::Core)?;
        self.check_current()?;
        match result {
            BhpanPathLookup::Found(item) => {
                if item.kind != BhpanItemKind::Folder {
                    return Err(RemoteError::Failed);
                }
                let files = self
                    .client
                    .bhpan_list_complete(&item.handle)
                    .await
                    .map_err(RemoteError::Core)?;
                self.check_current()?;
                let mut versions = Vec::with_capacity(files.len());
                for file in files {
                    if file.kind != BhpanItemKind::File {
                        return Err(RemoteError::Failed);
                    }
                    Publication::parse_file_name(&file.name).map_err(RemoteError::Local)?;
                    let version = self
                        .client
                        .bhpan_file_version(&file.handle, None)
                        .await
                        .map_err(RemoteError::Core)?;
                    self.check_current()?;
                    if version.name != file.name {
                        return Err(RemoteError::Failed);
                    }
                    versions.push(version);
                }
                self.folder = Some(item.handle);
                Ok(RemoteLocation::Found(versions))
            }
            BhpanPathLookup::Missing { parent, remaining } => {
                self.creation = Some((parent.handle, remaining));
                Ok(RemoteLocation::Missing)
            }
            BhpanPathLookup::Unknown { .. } => Ok(RemoteLocation::Unknown),
        }
    }
    fn directory_target(&self) -> Option<String> {
        let (_, remaining) = self.creation.as_ref()?;
        if remaining.is_empty() {
            return None;
        }
        let length = COMPONENTS.len().checked_sub(remaining.len())? + 1;
        serde_json::to_string(&COMPONENTS[..length]).ok()
    }
    async fn create_directory_once(
        &mut self,
        before_commit: BeforeCommit<'_>,
    ) -> Result<bool, RemoteError> {
        let (parent, remaining) = self.creation.as_ref().ok_or(RemoteError::Failed)?;
        let name = remaining.first().ok_or(RemoteError::Failed)?.clone();
        let prepared = self
            .client
            .bhpan_prepare_write(BhpanWriteIntent::CreateFolder {
                parent: parent.clone(),
                name,
            })
            .await
            .map_err(RemoteError::Core)?;
        self.check_current()?;
        before_commit()?;
        let receipt = self.client.bhpan_commit_write(&prepared.handle).await;
        self.check_current()?;
        match receipt {
            Ok(receipt) => Ok(receipt.item.is_some()),
            Err(error) if error.code == crate::error::ErrorCode::OutcomeUnknown => Ok(false),
            Err(error) => Err(RemoteError::Core(error)),
        }
    }
    async fn directory_exists(&mut self, target: &str) -> Result<bool, RemoteError> {
        let components: Vec<String> =
            serde_json::from_str(target).map_err(|_| RemoteError::Failed)?;
        if components.is_empty()
            || components.len() > COMPONENTS.len()
            || !components
                .iter()
                .zip(COMPONENTS)
                .all(|(actual, expected)| actual == expected)
        {
            return Err(RemoteError::Failed);
        }
        let result = self
            .client
            .bhpan_lookup_personal_path_complete(&components)
            .await;
        self.check_current()?;
        Ok(matches!(result.map_err(RemoteError::Core)?,
            BhpanPathLookup::Found(item) if item.kind == BhpanItemKind::Folder))
    }
    async fn read_version(&mut self, version: &Self::Version) -> Result<Vec<u8>, RemoteError> {
        if version.bytes > scratch::LIMIT {
            return Err(RemoteError::Core(crate::error::UbaaError::invalid_input(
                "日程同步正文超过容量上限",
            )));
        }
        let scratch = Scratch::new(self.scratch_root).map_err(RemoteError::Core)?;
        let receipt = self
            .client
            .bhpan_download_file_version(version, scratch.path(), false, BhpanTransfer::new())
            .await
            .map_err(RemoteError::Core)?;
        self.check_current()?;
        if receipt.version != *version {
            return Err(RemoteError::Failed);
        }
        std::fs::read(scratch.path()).map_err(|_| RemoteError::Core(scratch::failed()))
    }
    async fn publish_once(
        &mut self,
        identity: Publication,
        body: &[u8],
        before_commit: BeforeCommit<'_>,
    ) -> Result<RemoteCommit<Self::Version>, RemoteError> {
        let scratch = Scratch::new(self.scratch_root).map_err(RemoteError::Core)?;
        let path = scratch.write(body).map_err(RemoteError::Core)?;
        match self.upload(identity, path, before_commit).await {
            Err(RemoteError::Core(error))
                if error.code == crate::error::ErrorCode::OutcomeUnknown =>
            {
                Ok(RemoteCommit::OutcomeUnknown(None))
            }
            result => result,
        }
    }
}
