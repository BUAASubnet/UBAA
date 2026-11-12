//! 图书馆云打印的原生宿主合同，限定在直连会话。
#![allow(clippy::missing_errors_doc)]

use std::path::PathBuf;

use futures_util::{StreamExt as _, stream};

use crate::domain::RoutePolicy;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::features::cloud_print::{self, auth, read};
use crate::runtime::ClientRuntime;

use super::UbaaClient;

pub struct PrintDocument {
    pub id: String,
    pub name: String,
    pub date: String,
    pub time: String,
    pub bytes: Option<u64>,
    pub pages: Option<u32>,
    pub copies: Option<u64>,
    pub expired: bool,
}

pub struct PrintStation {
    pub name: String,
    pub group: Option<String>,
    pub state: String,
    pub papers: Vec<String>,
    pub capabilities: Vec<String>,
}

pub struct PrintRecord {
    pub date: String,
    pub time: String,
    pub pages: u64,
    pub paper: Option<String>,
    pub free_cents: i64,
    pub card_cents: i64,
    pub other_cents: i64,
}

pub struct PrintRecords {
    pub items: Vec<PrintRecord>,
    pub total_pages: u32,
}

pub struct PrintFile {
    pub path: PathBuf,
    pub name: String,
}

#[derive(Clone, Copy)]
pub struct PrintOptions {
    pub color: bool,
    pub paper: i32,
    pub duplex: u8,
    pub copies: u32,
    pub pages: Option<(u32, u32)>,
}

impl PrintOptions {
    fn validate(self) -> Result<()> {
        if !matches!(self.paper, -1 | 8 | 9)
            || !matches!(self.duplex, 1..=3)
            || !(1..=999).contains(&self.copies)
            || self.pages.is_some_and(|(from, to)| from == 0 || from > to)
        {
            return Err(UbaaError::invalid_input("打印参数无效"));
        }
        Ok(())
    }
}

impl UbaaClient {
    async fn print_runtime(&mut self) -> Result<&mut ClientRuntime> {
        self.guard_latest_session_ownership()?;
        self.direct_runtime.ensure_primary_client()?;
        if self.config.default == RoutePolicy::WebVpn {
            self.cloud_print = None;
            return Err(UbaaError::new(
                ErrorCode::Unsupported,
                ErrorKind::Input,
                false,
                "云打印当前只支持直连，请在设置中选择直连或自动",
            ));
        }
        crate::features::require_session(&self.direct_runtime)
            .map_err(|_| cloud_print::authentication_required())?;
        if self.cloud_print.as_ref().is_some_and(|runtime| {
            runtime.authentication_revoked()
                || runtime.authentication_generation()
                    != self.direct_runtime.authentication_generation()
                || runtime.ensure_session_revision().is_err()
        }) {
            self.cloud_print = None;
        }
        if self.cloud_print.is_none() {
            let mut runtime = self.direct_runtime.fork_with_cookie_filter(|_| false);
            let mut sso = self.direct_runtime.fork_with_cookie_filter(|c| {
                matches!(
                    c.domain.trim_start_matches('.'),
                    "sso.buaa.edu.cn" | "buaa.edu.cn"
                )
            });
            auth::login(&mut runtime, &mut sso).await?;
            self.cloud_print = Some(Box::new(runtime));
        }
        Ok(self.cloud_print.as_deref_mut().expect("已建立云打印会话"))
    }

    fn print_result<T>(&mut self, result: Result<T>) -> Result<T> {
        if result
            .as_ref()
            .is_err_and(|error| error.code == ErrorCode::AuthenticationRequired)
        {
            self.cloud_print = None;
        }
        result
    }

    pub async fn cloud_print_documents(&mut self, scans: bool) -> Result<Vec<PrintDocument>> {
        let result = read::documents(self.print_runtime().await?, scans).await;
        self.print_result(result)
    }

    pub async fn cloud_print_preview(&mut self, id: &str, page: u32) -> Result<Vec<u8>> {
        let jobs = self.cloud_print_documents(false).await?;
        let job = find(&jobs, id)?;
        let result = read::preview(self.print_runtime().await?, job, page).await;
        self.print_result(result)
    }

    pub async fn cloud_print_scan(&mut self, id: &str) -> Result<Vec<u8>> {
        let jobs = self.cloud_print_documents(true).await?;
        let job = find(&jobs, id)?;
        let result = read::scan_download(self.print_runtime().await?, job).await;
        self.print_result(result)
    }

    /// 并发下载同账号的扫描原件，按传入顺序合并成一个 PDF。
    pub async fn cloud_print_scan_pdf(&mut self, ids: Vec<String>) -> Result<Vec<u8>> {
        if ids.len() < 2 {
            return Err(UbaaError::invalid_input("请至少选择两份扫描 PDF"));
        }
        let jobs = self.cloud_print_documents(true).await?;
        let mut seen = std::collections::HashSet::new();
        let mut targets = Vec::with_capacity(ids.len());
        let mut size = 0_u64;
        for id in &ids {
            let job = find(&jobs, id)?;
            if !seen.insert(id) || job.expired {
                return Err(UbaaError::invalid_input("扫描件已过期或重复，本组未保存"));
            }
            size = size.saturating_add(job.bytes.unwrap_or_default());
            targets.push(job);
        }
        if size > 128 * 1024 * 1024 {
            return Err(UbaaError::invalid_input(
                "扫描原件合计超过 128 MiB，本组未保存",
            ));
        }
        let runtime = self.print_runtime().await?;
        let result = async {
            let parts = run_four_ordered(targets, |job| {
                let mut lane = runtime.fork_with_cookie_filter(|_| true);
                async move { read::scan_download(&mut lane, job).await }
            })
            .await
            .into_iter()
            .collect::<Result<Vec<_>>>()?;
            runtime.ensure_session_revision()?;
            let pdf = tokio::task::spawn_blocking(move || cloud_print::pdf::merge_scan_pdfs(parts))
                .await
                .map_err(|_| UbaaError::invalid_input("无法合并扫描 PDF，本组未保存"))??;
            runtime.ensure_session_revision()?;
            Ok(pdf)
        }
        .await;
        self.print_result(result)
    }

    /// 每个目标都从当前账号的最新列表解析；结果按请求顺序返回。
    pub async fn cloud_print_delete(
        &mut self,
        scans: bool,
        ids: Vec<String>,
    ) -> Result<Vec<Result<()>>> {
        valid_count(ids.len())?;
        let jobs = self.cloud_print_documents(scans).await?;
        let mut seen = std::collections::HashSet::new();
        let targets: Vec<_> = ids
            .iter()
            .map(|id| {
                if seen.insert(id.as_str()) {
                    find(&jobs, id)
                } else {
                    Err(UbaaError::invalid_input("重复的文档"))
                }
            })
            .collect();
        let runtime = self.print_runtime().await?;
        let mut results = Vec::with_capacity(ids.len());
        for target in targets {
            let result = match target {
                Ok(job) => read::delete(runtime, job, scans).await,
                Err(error) => Err(error),
            };
            let stop = result
                .as_ref()
                .is_err_and(|error| error.code == ErrorCode::OutcomeUnknown);
            results.push(result);
            if stop {
                results.resize_with(ids.len(), || {
                    Err(UbaaError::invalid_input("前一项结果待核对，未继续删除"))
                });
                break;
            }
        }
        Ok(results)
    }

    /// 单批最多四个文档同时上传；各请求单次发送且不复用响应 Cookie。
    pub async fn cloud_print_upload(
        &mut self,
        files: Vec<PrintFile>,
        options: PrintOptions,
    ) -> Result<Vec<Result<()>>> {
        valid_count(files.len())?;
        options.validate()?;
        let runtime = self.print_runtime().await?;
        Ok(run_four_ordered(files, |file| {
                    let mut lane = runtime.fork_with_cookie_filter(|_| true);
                    async move {
                        cloud_print::send_upload(&mut lane, &file.path, &file.name, options).await
                    }
        }).await)
    }

    pub async fn cloud_print_stations(&mut self) -> Result<Vec<PrintStation>> {
        let result = read::stations(self.print_runtime().await?).await;
        self.print_result(result)
    }

    pub async fn cloud_print_records(
        &mut self,
        begin: &str,
        end: &str,
        kind: u8,
        page: u32,
    ) -> Result<PrintRecords> {
        let result = read::records(self.print_runtime().await?, begin, end, kind, page).await;
        self.print_result(result)
    }
}

fn valid_count(count: usize) -> Result<()> {
    if (1..=20).contains(&count) {
        Ok(())
    } else {
        Err(UbaaError::invalid_input("每次请选择 1 至 20 个文档"))
    }
}

fn find<'a>(jobs: &'a [PrintDocument], id: &str) -> Result<&'a PrintDocument> {
    let mut matches = jobs.iter().filter(|job| job.id == id);
    let job = matches
        .next()
        .ok_or_else(|| UbaaError::invalid_input("该文档已不在列表中，请刷新"))?;
    if matches.next().is_some() {
        return Err(cloud_print::invalid());
    }
    Ok(job)
}

/// Free a lane as soon as any transfer completes and restore input order for the caller.
pub(crate) async fn run_four_ordered<T, R, F>(files: Vec<T>, send: impl FnMut(T) -> F) -> Vec<R>
where
    F: Future<Output = R>,
{
    let mut send = send;
    let mut results = stream::iter(files.into_iter().enumerate())
        .map(|(index, file)| {
            let send = send(file);
            async move { (index, send.await) }
        })
        .buffer_unordered(4)
        .collect::<Vec<_>>()
        .await;
    results.sort_unstable_by_key(|(index, _)| *index);
    results.into_iter().map(|(_, result)| result).collect()
}
