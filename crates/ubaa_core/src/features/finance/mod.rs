//! 财务收入读取与完整分页。
mod auth;
mod parser;
#[cfg(test)]
mod tests;
use crate::domain::FinanceIncomes;
use crate::error::{ErrorCode, Result};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;

use parser::invalid;

pub(crate) async fn incomes(runtime: &mut ClientRuntime) -> Result<FinanceIncomes> {
    for attempt in 0..2 {
        let result = read_all(runtime).await;
        if result
            .as_ref()
            .is_err_and(|e| e.code == ErrorCode::AuthenticationRequired)
        {
            runtime.feature_state().finance.clear();
            if attempt == 0 {
                continue;
            }
        }
        return result;
    }
    Err(invalid())
}
async fn read_all(runtime: &mut ClientRuntime) -> Result<FinanceIncomes> {
    let credential = auth::ensure(runtime).await?;
    let generation = runtime.feature_state().finance.generation();
    let expected = runtime.url("https://chaxun.icw.buaa.edu.cn/api-zhcx/getStudentSRCX")?;
    let mut entries = Vec::new();
    let mut ids = std::collections::HashSet::new();
    let mut expected_total = None;
    let mut page = 1_u32;
    loop {
        let body = serde_json::json!({"userId":credential.user,"currentPage":page,"limit":100})
            .to_string()
            .into_bytes();
        let request = HttpRequest::post(&expected, body)
            .with_header("Content-Type", "application/json")
            .with_header(
                "Authorization",
                format!("Bearer {}", credential.token.expose_secret()),
            );
        let response = runtime
            .request_with_pre_send_check(request, |r| auth::check(r, generation))
            .await?;
        auth::check(runtime, generation)?;
        if response.status == 401 {
            return Err(crate::error::UbaaError::new(
                ErrorCode::AuthenticationRequired,
                crate::error::ErrorKind::Authentication,
                false,
                "财务登录已失效",
            ));
        }
        if response.status != 200 || response.final_url != expected {
            return Err(invalid());
        }
        let (rows, total) = parser::page(&parser::envelope(&response.body)?)?;
        if expected_total.is_some_and(|previous| previous != total) || rows.len() > 100 {
            return Err(invalid());
        }
        expected_total = Some(total);
        let empty = rows.is_empty();
        for row in rows {
            let entry = parser::income(&row)?;
            if !ids.insert(entry.id.clone()) {
                return Err(invalid());
            }
            entries.push(entry);
        }
        if entries.len() == total {
            return Ok(FinanceIncomes {
                entries,
                total: u32::try_from(total).map_err(|_| invalid())?,
            });
        }
        if empty || entries.len() > total {
            return Err(invalid());
        }
        page = page.checked_add(1).ok_or_else(invalid)?;
    }
}
