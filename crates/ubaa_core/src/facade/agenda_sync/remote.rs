use super::{
    Binding,
    scratch::{self, Scratch},
};
use crate::{
    agenda::sync::coordinator::{
        BeforeCommit, RemoteCommit, RemoteError, RemoteLocation, SyncRemote,
    },
    domain::bhpan::{
        BhpanFileVersion, BhpanItemKind, BhpanPathLookup, BhpanVersionUploadOutcome,
        BhpanWriteIntent,
    },
    facade::{UbaaClient, bhpan::BhpanTransfer},
};
use async_trait::async_trait;
use std::path::{Path, PathBuf};

pub(super) struct BhpanRemote<'a> {
    client: &'a mut UbaaClient,
    binding: Binding,
    scratch_root: &'a Path,
    creation: Option<(String, Vec<String>)>,
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
        }
    }
    async fn upload(
        &mut self,
        base: Option<&BhpanFileVersion>,
        path: PathBuf,
        before_commit: BeforeCommit<'_>,
    ) -> Result<RemoteCommit<BhpanFileVersion>, RemoteError> {
        let transfer = BhpanTransfer::new();
        let prepared = if let Some(base) = base {
            self.client
                .bhpan_prepare_version_upload(base, path, transfer)
                .await
        } else {
            let (parent, remaining) = self.creation.as_ref().ok_or(RemoteError::Failed)?;
            if remaining.as_slice() != ["agenda.json"] {
                return Err(RemoteError::Failed);
            }
            self.client
                .bhpan_prepare_upload(parent, path, "agenda.json", transfer)
                .await
        }
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
        if self.client.bhpan_capabilities().conditional_replace
            != crate::domain::bhpan::BhpanCapability::Available
        {
            return Err(RemoteError::Unverified);
        }
        Ok(())
    }
    fn same_object(&self, left: &Self::Version, right: &Self::Version) -> bool {
        left.docid == right.docid
    }
    fn object_key(&self, version: &Self::Version) -> String {
        version.docid.clone()
    }
    async fn locate(&mut self) -> Result<RemoteLocation<Self::Version>, RemoteError> {
        let result = self
            .client
            .bhpan_lookup_personal_path(&["UBAA".into(), "agenda.json".into()])
            .await
            .map_err(RemoteError::Core)?;
        self.check_current()?;
        match result {
            BhpanPathLookup::Found(item) => {
                let version = self
                    .client
                    .bhpan_file_version(&item.handle, None)
                    .await
                    .map_err(RemoteError::Core)?;
                self.check_current()?;
                Ok(RemoteLocation::Found(version))
            }
            BhpanPathLookup::Missing { parent, remaining } => {
                self.creation = Some((parent.handle, remaining));
                Ok(RemoteLocation::Missing)
            }
            BhpanPathLookup::Unknown {
                parent, remaining, ..
            } => {
                self.creation = Some((parent.handle, remaining));
                Ok(RemoteLocation::Unknown)
            }
        }
    }
    fn needs_directory(&self) -> bool {
        self.creation
            .as_ref()
            .is_some_and(|(_, remaining)| remaining.as_slice() == ["UBAA", "agenda.json"])
    }
    async fn create_directory_once(
        &mut self,
        before_commit: BeforeCommit<'_>,
    ) -> Result<bool, RemoteError> {
        let (parent, _) = self.creation.as_ref().ok_or(RemoteError::Failed)?;
        let prepared = self
            .client
            .bhpan_prepare_write(BhpanWriteIntent::CreateFolder {
                parent: parent.clone(),
                name: "UBAA".into(),
            })
            .await
            .map_err(RemoteError::Core)?;
        self.check_current()?;
        before_commit()?;
        let receipt = self.client.bhpan_commit_write(&prepared.handle).await;
        self.check_current()?;
        match receipt {
            Ok(receipt) => {
                let Some(item) = receipt.item else {
                    return Ok(false);
                };
                self.creation = Some((item.handle, vec!["agenda.json".into()]));
                Ok(true)
            }
            Err(error) if error.code == crate::error::ErrorCode::OutcomeUnknown => Ok(false),
            Err(error) => Err(RemoteError::Core(error)),
        }
    }
    async fn directory_exists(&mut self) -> Result<bool, RemoteError> {
        let result = self
            .client
            .bhpan_lookup_personal_path(&["UBAA".into()])
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
        base: Option<&Self::Version>,
        body: &[u8],
        before_commit: BeforeCommit<'_>,
    ) -> Result<RemoteCommit<Self::Version>, RemoteError> {
        let scratch = Scratch::new(self.scratch_root).map_err(RemoteError::Core)?;
        let path = scratch.write(body).map_err(RemoteError::Core)?;
        match self.upload(base, path, before_commit).await {
            Err(RemoteError::Core(error))
                if error.code == crate::error::ErrorCode::OutcomeUnknown =>
            {
                Ok(RemoteCommit::OutcomeUnknown(None))
            }
            result => result,
        }
    }
}
