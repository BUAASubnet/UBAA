//! 云打印的 typed 宿主投影。
#![allow(clippy::missing_errors_doc)]

use crate::api::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, catch_panic, disposed_error,
};
use ubaa_core::facade::{UbaaError, cloud_print as core};

pub struct BridgePrintDocument {
    pub id: String,
    pub name: String,
    pub date: String,
    pub time: String,
    pub bytes: Option<u64>,
    pub pages: Option<u32>,
    pub copies: Option<u64>,
    pub expired: bool,
}

pub struct BridgePrintStation {
    pub name: String,
    pub group: Option<String>,
    pub state: String,
    pub papers: Vec<String>,
    pub capabilities: Vec<String>,
}

pub struct BridgePrintRecord {
    pub date: String,
    pub time: String,
    pub pages: u64,
    pub paper: Option<String>,
    pub free_cents: i64,
    pub card_cents: i64,
    pub other_cents: i64,
}

pub struct BridgePrintRecords {
    pub items: Vec<BridgePrintRecord>,
    pub total_pages: u32,
}

pub struct BridgePrintFile {
    pub path: String,
    pub name: String,
}

pub enum BridgePrintPaper {
    Original,
    A4,
    A3,
}

pub enum BridgePrintDuplex {
    Single,
    LongEdge,
    ShortEdge,
}

pub enum BridgePrintRecordKind {
    Print,
    Copy,
    Scan,
}

pub struct BridgePrintOptions {
    pub color: bool,
    pub paper: BridgePrintPaper,
    pub duplex: BridgePrintDuplex,
    pub copies: u32,
    pub from_page: Option<u32>,
    pub to_page: Option<u32>,
}

fn error(value: UbaaError) -> BridgeError {
    BridgeError::from_core(value, Some(BridgeConnectionMode::Direct))
}

impl BridgeClient {
    pub async fn cloud_print_documents(
        &self,
        scans: bool,
    ) -> Result<Vec<BridgePrintDocument>, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let rows = g
                .as_mut()
                .ok_or_else(disposed_error)?
                .cloud_print_documents(scans)
                .await
                .map_err(error)?;
            Ok(rows
                .into_iter()
                .map(|row| BridgePrintDocument {
                    id: row.id,
                    name: row.name,
                    date: row.date,
                    time: row.time,
                    bytes: row.bytes,
                    pages: row.pages,
                    copies: row.copies,
                    expired: row.expired,
                })
                .collect())
        })
        .await
    }

    pub async fn cloud_print_preview(&self, id: String, page: u32) -> Result<Vec<u8>, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            g.as_mut()
                .ok_or_else(disposed_error)?
                .cloud_print_preview(&id, page)
                .await
                .map_err(error)
        })
        .await
    }

    pub async fn cloud_print_scan(&self, id: String) -> Result<Vec<u8>, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            g.as_mut()
                .ok_or_else(disposed_error)?
                .cloud_print_scan(&id)
                .await
                .map_err(error)
        })
        .await
    }

    pub async fn cloud_print_scan_pdf(&self, ids: Vec<String>) -> Result<Vec<u8>, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            g.as_mut()
                .ok_or_else(disposed_error)?
                .cloud_print_scan_pdf(ids)
                .await
                .map_err(error)
        })
        .await
    }

    pub async fn cloud_print_delete(
        &self,
        scans: bool,
        ids: Vec<String>,
    ) -> Result<Vec<Option<BridgeError>>, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let results = g
                .as_mut()
                .ok_or_else(disposed_error)?
                .cloud_print_delete(scans, ids)
                .await
                .map_err(error)?;
            Ok(results.into_iter().map(|r| r.err().map(error)).collect())
        })
        .await
    }

    pub async fn cloud_print_upload(
        &self,
        files: Vec<BridgePrintFile>,
        options: BridgePrintOptions,
    ) -> Result<Vec<Option<BridgeError>>, BridgeError> {
        catch_panic(async {
            let pages = match (options.from_page, options.to_page) {
                (None, None) => None,
                (Some(from), Some(to)) => Some((from, to)),
                _ => return Err(error(UbaaError::invalid_input("请填写完整的打印页码范围"))),
            };
            let options = core::PrintOptions {
                color: options.color,
                paper: match options.paper {
                    BridgePrintPaper::Original => -1,
                    BridgePrintPaper::A4 => 9,
                    BridgePrintPaper::A3 => 8,
                },
                duplex: match options.duplex {
                    BridgePrintDuplex::Single => 1,
                    BridgePrintDuplex::LongEdge => 2,
                    BridgePrintDuplex::ShortEdge => 3,
                },
                copies: options.copies,
                pages,
            };
            let files = files
                .into_iter()
                .map(|file| core::PrintFile {
                    path: file.path.into(),
                    name: file.name,
                })
                .collect();
            let mut g = self.inner.lock().await;
            let results = g
                .as_mut()
                .ok_or_else(disposed_error)?
                .cloud_print_upload(files, options)
                .await
                .map_err(error)?;
            Ok(results.into_iter().map(|r| r.err().map(error)).collect())
        })
        .await
    }

    pub async fn cloud_print_stations(&self) -> Result<Vec<BridgePrintStation>, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let rows = g
                .as_mut()
                .ok_or_else(disposed_error)?
                .cloud_print_stations()
                .await
                .map_err(error)?;
            Ok(rows
                .into_iter()
                .map(|row| BridgePrintStation {
                    name: row.name,
                    group: row.group,
                    state: row.state,
                    papers: row.papers,
                    capabilities: row.capabilities,
                })
                .collect())
        })
        .await
    }

    pub async fn cloud_print_records(
        &self,
        begin: String,
        end: String,
        kind: BridgePrintRecordKind,
        page: u32,
    ) -> Result<BridgePrintRecords, BridgeError> {
        catch_panic(async {
            let mut g = self.inner.lock().await;
            let kind = match kind {
                BridgePrintRecordKind::Print => 1,
                BridgePrintRecordKind::Copy => 2,
                BridgePrintRecordKind::Scan => 4,
            };
            let result = g
                .as_mut()
                .ok_or_else(disposed_error)?
                .cloud_print_records(&begin, &end, kind, page)
                .await
                .map_err(error)?;
            Ok(BridgePrintRecords {
                total_pages: result.total_pages,
                items: result
                    .items
                    .into_iter()
                    .map(|row| BridgePrintRecord {
                        date: row.date,
                        time: row.time,
                        pages: row.pages,
                        paper: row.paper,
                        free_cents: row.free_cents,
                        card_cents: row.card_cents,
                        other_cents: row.other_cents,
                    })
                    .collect(),
            })
        })
        .await
    }
}
