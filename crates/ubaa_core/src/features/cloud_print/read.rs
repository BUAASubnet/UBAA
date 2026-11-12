use base64::{Engine as _, engine::general_purpose::STANDARD};
use serde_json::{Value, json};

use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::facade::cloud_print::{PrintDocument, PrintRecord, PrintRecords, PrintStation};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

use super::{PAGE, endpoint, envelope, integer, invalid, request, timestamped, unknown};

pub(crate) async fn documents(
    runtime: &mut ClientRuntime,
    scans: bool,
) -> Result<Vec<PrintDocument>> {
    let path = if scans { "Scan/Get" } else { "PrintJob/Get" };
    let response = request(runtime, HttpRequest::get(timestamped(path).as_str())).await?;
    let value = envelope(&response)?;
    rows(&value)?
        .iter()
        .map(|row| document(row, scans))
        .collect()
}

fn document(row: &Value, scans: bool) -> Result<PrintDocument> {
    let (name, date, time, bytes, pages, copies, expired) = if scans {
        (
            text(row, "szDisplayName")?,
            field(row, "dwSubmitDate")?,
            field(row, "dwSubmitTime")?,
            Some(natural(row, "dwFileSize")?),
            None,
            None,
            number(row, "dwStatus")? & 256 != 0,
        )
    } else {
        let detail: Value =
            serde_json::from_str(&text(row, "szPaperDetail")?).map_err(|_| invalid())?;
        let pages = detail.get(0).and_then(|paper| {
            natural(paper, "dwBWPages")
                .ok()?
                .checked_add(natural(paper, "dwColorPages").ok()?)
        });
        (
            text(row, "szJobName")?,
            field(row, "dwCreateDate")?,
            field(row, "dwCreateTime")?,
            None,
            pages.and_then(|p| u32::try_from(p).ok()),
            Some(natural(row, "dwCopies")?),
            false,
        )
    };
    Ok(PrintDocument {
        id: field(row, "dwJobId")?,
        name,
        date,
        time,
        bytes,
        pages,
        copies,
        expired,
    })
}

pub(crate) async fn preview(
    runtime: &mut ClientRuntime,
    job: &PrintDocument,
    page: u32,
) -> Result<Vec<u8>> {
    if page == 0 || job.pages.is_none_or(|total| page > total) {
        return Err(UbaaError::invalid_input("预览页码不可用"));
    }
    let mut url = timestamped("PrintJob/PreviewPage");
    url.query_pairs_mut()
        .append_pair("dwJobId", &job.id)
        .append_pair("dwCreateTime", &job.time)
        .append_pair("pageNo", &page.to_string());
    let response = request(runtime, HttpRequest::get(url.as_str())).await?;
    let value = envelope(&response).map_err(|error| {
        let image = job.name.rsplit_once('.').is_some_and(|(_, ext)| {
            matches!(ext.to_ascii_lowercase().as_str(), "jpg" | "jpeg" | "png")
        });
        if image && error.code == ErrorCode::BusinessUnavailable {
            UbaaError::new(
                ErrorCode::Unsupported,
                ErrorKind::Upstream,
                false,
                "打印站无法预览这份原格式图片。重新上传后会转为可预览的 PDF。",
            )
        } else {
            error
        }
    })?;
    let bytes = STANDARD
        .decode(value["result"].as_str().ok_or_else(invalid)?)
        .map_err(|_| invalid())?;
    if !bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Err(invalid());
    }
    Ok(bytes)
}

pub(crate) async fn scan_download(
    runtime: &mut ClientRuntime,
    job: &PrintDocument,
) -> Result<Vec<u8>> {
    if job.expired {
        return Err(UbaaError::invalid_input("扫描文档已过期"));
    }
    let mut url = endpoint("Scan/Download");
    url.query_pairs_mut().append_pair("dwJobId", &job.id);
    let response = request(runtime, HttpRequest::get(url.as_str())).await?;
    if matches!(response.status, 401 | 403) {
        return Err(super::authentication_required());
    }
    if response.status != 200 || response.body.is_empty() {
        return Err(invalid());
    }
    let mime = response
        .header_first("content-type")
        .unwrap_or_default()
        .to_ascii_lowercase();
    scan_payload(response.body, &mime, job.bytes)
}

fn scan_payload(mut body: Vec<u8>, mime: &str, listed_size: Option<u64>) -> Result<Vec<u8>> {
    if mime.starts_with("text/html") || mime.contains("json") {
        return Err(invalid());
    }
    let size = listed_size
        .and_then(|bytes| usize::try_from(bytes).ok())
        .filter(|&bytes| bytes != 0)
        .ok_or_else(invalid)?;
    if body.len() == size {
        return Ok(body);
    }
    // 部分原件的下载响应在列表声明的 PDF 边界之后附带少量字节。
    // 仅在 PDF 头和列表边界处的独立 EOF 行均成立时截取；拒绝不完整文件。
    if mime.split(';').next() == Some("application/octet-stream")
        && body.len().saturating_sub(size) <= 16
        && body.starts_with(b"%PDF-")
        && body.get(..size).is_some_and(|original| {
            original
                .trim_ascii_end()
                .strip_suffix(b"%%EOF")
                .is_some_and(|prefix| prefix.ends_with(b"\n") || prefix.ends_with(b"\r"))
        })
    {
        body.truncate(size);
        return Ok(body);
    }
    Err(UbaaError::new(
        ErrorCode::BusinessUnavailable,
        ErrorKind::Upstream,
        true,
        "打印站未返回完整的扫描文件，请稍后重试",
    ))
}

pub(crate) async fn delete(
    runtime: &mut ClientRuntime,
    job: &PrintDocument,
    scan: bool,
) -> Result<()> {
    if job.expired {
        return Err(UbaaError::invalid_input("扫描文档已过期"));
    }
    let (path, payload) = if scan {
        ("Scan/Del", json!({ "dwJobId": job.id }))
    } else {
        (
            "PrintJob/Del",
            json!({ "dwJobId": job.id, "dwOldJobId": job.id }),
        )
    };
    let url = endpoint(path);
    let response = runtime
        .request_non_idempotent(
            HttpRequest::post(url.as_str(), payload.to_string().into_bytes())
                .with_header("Content-Type", "application/json")
                .with_header("Referer", PAGE),
        )
        .await?;
    runtime.ensure_session_revision().map_err(|_| unknown())?;
    if !crate::ports::same_url(&response.final_url, url.as_str()) {
        return Err(unknown());
    }
    match envelope(&response) {
        Ok(_) => Ok(()),
        Err(error) if error.code == crate::error::ErrorCode::BusinessUnavailable => Err(error),
        Err(_) => Err(unknown()),
    }
}

pub(crate) async fn stations(runtime: &mut ClientRuntime) -> Result<Vec<PrintStation>> {
    let groups = envelope(
        &request(
            runtime,
            HttpRequest::get(endpoint("Station/GetSrvList").as_str()),
        )
        .await?,
    )?;
    let devices = envelope(
        &request(
            runtime,
            HttpRequest::get(timestamped("Station/GetList").as_str()),
        )
        .await?,
    )?;
    let groups = rows(&groups)?;
    rows(&devices)?
        .iter()
        .map(|row| {
            let id = number(row, "dwDevSN")? / 1000;
            let group = groups.iter().find(|g| number(g, "dwSN").ok() == Some(id));
            station(row, group)
        })
        .collect()
}

pub(crate) fn station(row: &Value, group: Option<&Value>) -> Result<PrintStation> {
    // 官网脚本的掩码以十进制表示：20、200、400、800、1000、2000、10000。
    const UNAVAILABLE: i64 = 0x0014 | 0x00c8 | 0x0190 | 0x0320 | 0x03e8 | 0x07d0 | 0x2710;
    let status = number(row, "dwStatus")?;
    let state = if status & UNAVAILABLE != 0 {
        "不可用"
    } else if status & 2 != 0 {
        "忙碌"
    } else if status & 1 != 0 {
        "空闲"
    } else if status == 0 {
        "未开放"
    } else {
        "不可用"
    };
    let mut papers = Vec::new();
    for key in [
        "dwTrayPaper1",
        "dwTrayPaper2",
        "dwTrayPaper3",
        "dwTrayPaper4",
    ] {
        let paper = match row.get(key).and_then(integer) {
            Some(9) => "A4",
            Some(8) => "A3",
            _ => continue,
        };
        if !papers.iter().any(|value| value == paper) {
            papers.push(paper.to_owned());
        }
    }
    let property = row.get("dwProperty").and_then(integer).unwrap_or_default();
    let capabilities = [(1, "打印"), (2, "复印"), (4, "扫描"), (8, "彩色")]
        .into_iter()
        .filter(|(flag, _)| property & flag != 0)
        .map(|(_, label)| label.to_owned())
        .collect();
    Ok(PrintStation {
        name: text(row, "szName")?,
        group: group.and_then(|g| text(g, "szName").ok()),
        state: state.into(),
        papers,
        capabilities,
    })
}

pub(crate) async fn records(
    runtime: &mut ClientRuntime,
    begin: &str,
    end: &str,
    kind: u8,
    page: u32,
) -> Result<PrintRecords> {
    let parse = |s: &str| {
        if s.len() != 8 || !s.bytes().all(|b| b.is_ascii_digit()) {
            return Err(UbaaError::invalid_input("使用记录日期无效"));
        }
        chrono::NaiveDate::parse_from_str(s, "%Y%m%d")
            .map_err(|_| UbaaError::invalid_input("使用记录日期无效"))
    };
    if parse(begin)? > parse(end)? || !matches!(kind, 1 | 2 | 4) || page == 0 {
        return Err(UbaaError::invalid_input("使用记录查询条件无效"));
    }
    let query = json!({"dwBeginDate":begin, "dwEndDate":end, "dwType":kind, "dwPageNo":page, "dwRowCount":5});
    let response = request(
        runtime,
        HttpRequest::post(
            timestamped("Report/DetailPageEx").as_str(),
            query.to_string().into_bytes(),
        )
        .with_header("Content-Type", "application/json"),
    )
    .await?;
    let value = envelope(&response)?;
    let items = rows(&value)?
        .iter()
        .map(|row| {
            Ok(PrintRecord {
                date: field(row, "dwDate")?,
                time: field(row, "dwTime")?,
                pages: natural(row, "dwPages")?,
                paper: match row.get("dwPaperID").and_then(integer) {
                    Some(9) => Some("A4".into()),
                    Some(8) => Some("A3".into()),
                    _ => None,
                },
                free_cents: number(row, "dwUsedFreeMoney")?,
                card_cents: number(row, "dwUsedCardMoney")?,
                other_cents: number(row, "dwUsedMoney")?,
            })
        })
        .collect::<Result<Vec<_>>>()?;
    let total = if items.is_empty() && page == 1 {
        0
    } else {
        natural(&value, "dwTotalPage")?
    };
    Ok(PrintRecords {
        items,
        total_pages: u32::try_from(total).map_err(|_| invalid())?,
    })
}

fn rows(value: &Value) -> Result<&[Value]> {
    match value.get("result") {
        Some(Value::Array(rows)) => Ok(rows),
        Some(Value::Null) => Ok(&[]),
        _ => Err(invalid()),
    }
}

fn text(value: &Value, field: &str) -> Result<String> {
    value[field]
        .as_str()
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
        .ok_or_else(invalid)
}

fn number(value: &Value, field: &str) -> Result<i64> {
    integer(&value[field]).ok_or_else(invalid)
}

fn natural(value: &Value, field: &str) -> Result<u64> {
    u64::try_from(number(value, field)?).map_err(|_| invalid())
}

fn field(value: &Value, field: &str) -> Result<String> {
    if let Some(text) = value[field]
        .as_str()
        .filter(|s| !s.is_empty() && s.len() <= 24 && s.bytes().all(|b| b.is_ascii_digit()))
    {
        return Ok(text.to_owned());
    }
    Ok(natural(value, field)?.to_string())
}

#[cfg(test)]
mod scan_tests {
    use super::scan_payload;

    #[test]
    fn cloud_print_scan_discards_small_suffix_only_after_complete_pdf() {
        const MIME: &str = "application/octet-stream";
        let original = b"%PDF-1.7\nsynthetic body\n%%EOF\n";
        let listed_size = Some(original.len() as u64);
        let download = [original.as_slice(), b"fixture!"].concat();

        assert_eq!(
            scan_payload(download.clone(), MIME, listed_size).unwrap(),
            original
        );
        assert!(scan_payload(download.clone(), "text/html", listed_size).is_err());
        assert!(scan_payload(download, MIME, Some(original.len() as u64 - 3)).is_err());
        assert!(scan_payload(original[..original.len() - 1].to_vec(), MIME, listed_size).is_err());
        let excess = [original.as_slice(), &[42; 17]].concat();
        assert!(scan_payload(excess, MIME, listed_size).is_err());
        assert_eq!(
            scan_payload(original.to_vec(), MIME, listed_size).unwrap(),
            original
        );
    }
}
