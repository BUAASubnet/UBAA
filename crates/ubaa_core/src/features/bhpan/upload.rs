use super::transfer::BhpanTransfer;
use crate::domain::bhpan::BhpanTransferPhase;
use crate::error::{Result, UbaaError};
use md5::{Digest, Md5};
use std::fs::{File, Metadata};
use std::io::{Read, Seek};
use std::path::PathBuf;

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
    pub(crate) fn select(path: PathBuf, transfer: &BhpanTransfer) -> Result<Self> {
        transfer.ensure_active()?;
        let file = File::open(&path).map_err(|_| local())?;
        let metadata = file.metadata().map_err(|_| local())?;
        if !metadata.is_file() {
            return Err(local());
        }
        let source = Self {
            file,
            path,
            length: metadata.len(),
            metadata,
            slice_md5: String::new(),
            md5: String::new(),
            crc32: String::new(),
        };
        Ok(source)
    }
    pub(crate) fn open(path: PathBuf, transfer: &BhpanTransfer) -> Result<Self> {
        let mut source = Self::select(path, transfer)?;
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
