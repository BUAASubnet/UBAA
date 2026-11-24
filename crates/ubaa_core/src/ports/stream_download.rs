use std::{
    fs::OpenOptions,
    path::{Path, PathBuf},
};

use super::HttpResponse;
use crate::error::{Result, UbaaError};
use futures_util::{Stream, TryStreamExt};
use tokio::io::AsyncWriteExt;

const BODY_LIMIT: usize = 64 * 1024;

#[cfg(test)]
mod tests;

pub struct StreamSink {
    destination: PathBuf,
    limit: u64,
    pending: Option<Pending>,
    truncated: bool,
}

struct Pending {
    path: PathBuf,
    byte_len: u64,
}

impl Drop for Pending {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.path);
    }
}

pub(crate) enum StreamDownload {
    Body {
        response: HttpResponse,
        truncated: bool,
    },
    File {
        final_path: PathBuf,
        byte_len: u64,
        content_disposition_filename: Option<String>,
    },
}

fn local_error() -> UbaaError {
    UbaaError::invalid_input("无法写入所选下载位置")
}

impl StreamSink {
    pub(super) fn capture_kind(&self) -> &'static str {
        if self.pending.is_some() {
            "streamed_to_temp_file"
        } else if self.truncated {
            "truncated"
        } else {
            "complete"
        }
    }
    pub(crate) fn new(destination: &Path, limit: u64) -> Result<Self> {
        if destination.file_name().is_none() {
            return Err(local_error());
        }
        Ok(Self {
            destination: destination.into(),
            limit,
            pending: None,
            truncated: false,
        })
    }

    pub(crate) async fn receive<Chunk: AsRef<[u8]>, Chunks: Stream<Item = Result<Chunk>>>(
        &mut self,
        mut response: HttpResponse,
        chunks: Chunks,
    ) -> Result<HttpResponse> {
        let mut chunks = std::pin::pin!(chunks);
        let content_type = response
            .header_first("Content-Type")
            .unwrap_or("")
            .to_ascii_lowercase();
        if response.status != 200
            || ["json", "text/html", "text/plain"]
                .iter()
                .any(|kind| content_type.contains(kind))
        {
            while let Some(chunk) = chunks.try_next().await? {
                let bytes = chunk.as_ref();
                let count = bytes.len().min(BODY_LIMIT - response.body.len());
                response.body.extend_from_slice(&bytes[..count]);
                if count < bytes.len() {
                    self.truncated = true;
                    break;
                }
            }
            return Ok(response);
        }
        let mismatch = || UbaaError::upstream_changed("下载长度与响应声明不符");
        let too_large =
            || UbaaError::invalid_input(format!("文件超过下载上限（{} 字节）", self.limit));
        let expected = response
            .header_first("Content-Length")
            .map(str::parse::<u64>)
            .transpose()
            .map_err(|_| mismatch())?;
        if expected.is_some_and(|length| length > self.limit) {
            return Err(too_large());
        }
        let path = self
            .destination
            .with_file_name(format!(".ubaa-download-{}.part", uuid::Uuid::new_v4()));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let file = options.open(&path).map_err(|_| local_error())?;
        let mut pending = Pending { path, byte_len: 0 };
        let mut file = tokio::fs::File::from_std(file);
        while let Some(chunk) = chunks.try_next().await? {
            crate::facade::operation_control::check()?;
            let bytes = chunk.as_ref();
            pending.byte_len = pending
                .byte_len
                .checked_add(bytes.len() as u64)
                .filter(|length| *length <= self.limit)
                .ok_or_else(too_large)?;
            file.write_all(bytes).await.map_err(|_| local_error())?;
        }
        if expected.is_some_and(|length| length != pending.byte_len) {
            return Err(mismatch());
        }
        file.flush().await.map_err(|_| local_error())?;
        file.sync_all().await.map_err(|_| local_error())?;
        self.pending = Some(pending);
        Ok(response)
    }

    #[cfg(feature = "test-contract")]
    /// 按同一分块策略接收确定性夹具响应。
    /// # Errors
    /// 长度、写入或操作状态检查失败时返回错误。
    pub async fn fixture_response(&mut self, mut response: HttpResponse) -> Result<HttpResponse> {
        let body = std::mem::take(&mut response.body);
        self.receive(
            response,
            futures_util::stream::iter(body.chunks(8192).map(Ok)),
        )
        .await
    }

    pub(crate) fn deliver(self, response: HttpResponse) -> Result<StreamDownload> {
        let Some(pending) = self.pending else {
            return Ok(StreamDownload::Body {
                response,
                truncated: self.truncated,
            });
        };
        let filename = response
            .header_first("Content-Disposition")
            .and_then(|header| {
                header
                    .split(';')
                    .skip(1)
                    .filter_map(|part| part.trim().split_once('='))
                    .find(|(key, _)| key.trim().eq_ignore_ascii_case("filename"))
            })
            .map(|(_, value)| value.trim().trim_matches('"').to_owned());
        std::fs::rename(&pending.path, &self.destination).map_err(|_| local_error())?;
        Ok(StreamDownload::File {
            final_path: self.destination,
            byte_len: pending.byte_len,
            content_disposition_filename: filename,
        })
    }
}
