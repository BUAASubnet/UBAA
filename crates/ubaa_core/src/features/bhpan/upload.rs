use crate::domain::bhpan::BhpanTransferPhase;
use crate::domain::bhpan::transfer::BhpanTransfer;
use crate::error::{Result, UbaaError};
use md5::{Digest, Md5};
use std::fs::{File, Metadata};
use std::io::{Read, Seek};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// 本机上传源。公共命令可在解析目标前记录用户选择的文件版本。
#[derive(Clone)]
pub struct BhpanUploadSource {
    path: PathBuf,
    expected: Option<(u64, SystemTime)>,
}
impl From<PathBuf> for BhpanUploadSource {
    fn from(path: PathBuf) -> Self {
        Self {
            path,
            expected: None,
        }
    }
}
impl BhpanUploadSource {
    /// 记录文件长度及修改时间，不读取正文。
    /// # Errors
    /// 无法打开普通文件或读取其修改时间时拒绝。
    pub fn capture(path: PathBuf) -> Result<Self> {
        let metadata = File::open(&path)
            .and_then(|file| file.metadata())
            .map_err(|_| local())?;
        if !metadata.is_file() {
            return Err(local());
        }
        let expected = Some((metadata.len(), metadata.modified().map_err(|_| local())?));
        Ok(Self { path, expected })
    }
    /// 返回用户选择的本机路径。
    #[must_use]
    pub fn path(&self) -> &Path {
        &self.path
    }
    /// 在开始查找远端目标前拒绝已经变化的文件。
    /// # Errors
    /// 文件不可读或版本变化时拒绝。
    pub fn verify_current(&self) -> Result<()> {
        self.check(&std::fs::metadata(&self.path).map_err(|_| local())?)
    }
    fn check(&self, metadata: &Metadata) -> Result<()> {
        if !metadata.is_file()
            || self.expected.is_some_and(|(length, modified)| {
                metadata.len() != length || metadata.modified().ok() != Some(modified)
            })
        {
            return Err(local());
        }
        Ok(())
    }
}

pub(crate) struct FileSnapshot {
    file: File,
    path: PathBuf,
    metadata: Metadata,
    pub length: u64,
    pub slice_md5: String,
    pub md5: String,
    pub crc32: String,
}
fn local() -> UbaaError {
    UbaaError::invalid_input("本机文件不可读或选择后已变化，请重新选择")
}
impl FileSnapshot {
    pub(crate) fn select(selection: BhpanUploadSource, transfer: &BhpanTransfer) -> Result<Self> {
        transfer.ensure_active()?;
        let file = File::open(&selection.path).map_err(|_| local())?;
        let metadata = file.metadata().map_err(|_| local())?;
        selection.check(&metadata)?;
        let source = Self {
            file,
            path: selection.path,
            length: metadata.len(),
            metadata,
            slice_md5: String::new(),
            md5: String::new(),
            crc32: String::new(),
        };
        Ok(source)
    }
    pub(crate) fn open(selection: BhpanUploadSource, transfer: &BhpanTransfer) -> Result<Self> {
        let mut source = Self::select(selection, transfer)?;
        transfer.set(
            BhpanTransferPhase::HashingMini,
            0,
            source.length.min(200 * 1024),
        );
        let mut hash = Md5::new();
        let mut remaining = source.length.min(200 * 1024);
        let mut buffer = vec![0u8; 64 * 1024];
        while remaining > 0 {
            transfer.ensure_active()?;
            let length =
                usize::try_from(remaining.min(buffer.len() as u64)).map_err(|_| local())?;
            source
                .file
                .read_exact(&mut buffer[..length])
                .map_err(|_| local())?;
            hash.update(&buffer[..length]);
            remaining -= length as u64;
            transfer.advance(length as u64);
        }
        source.slice_md5 = hex::encode(hash.finalize());
        source.file.rewind().map_err(|_| local())?;
        source.verify()?;
        Ok(source)
    }
    pub(crate) fn full(mut self, transfer: &BhpanTransfer) -> Result<Self> {
        transfer.set(BhpanTransferPhase::HashingFull, 0, self.length);
        let mut hash = Md5::new();
        let mut crc = crc32fast::Hasher::new();
        let mut buffer = vec![0u8; 64 * 1024];
        let mut length = 0u64;
        loop {
            transfer.ensure_active()?;
            let n = self.file.read(&mut buffer).map_err(|_| local())?;
            if n == 0 {
                break;
            }
            hash.update(&buffer[..n]);
            crc.update(&buffer[..n]);
            length += n as u64;
            transfer.advance(n as u64);
        }
        if length != self.length {
            return Err(local());
        }
        self.md5 = hex::encode(hash.finalize());
        self.crc32 = format!("{:08x}", crc.finalize());
        self.verify()?;
        Ok(self)
    }
    pub(crate) fn range(&self, offset: u64, length: u64) -> Result<crate::ports::HttpFileRange> {
        self.verify()?;
        if offset
            .checked_add(length)
            .is_none_or(|end| end > self.length)
        {
            return Err(local());
        }
        Ok(crate::ports::HttpFileRange {
            file: self.file.try_clone().map_err(|_| local())?,
            offset,
            length,
        })
    }
    pub(crate) fn verify(&self) -> Result<()> {
        let current = self.file.metadata().map_err(|_| local())?;
        let selected = std::fs::metadata(&self.path).map_err(|_| local())?;
        let same = |m: &Metadata| {
            m.is_file()
                && m.len() == self.length
                && m.modified().ok() == self.metadata.modified().ok()
        };
        if same(&current) && same(&selected) {
            Ok(())
        } else {
            Err(local())
        }
    }
}
