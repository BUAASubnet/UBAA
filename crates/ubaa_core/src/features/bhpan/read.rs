use super::{
    parse,
    wire::{self, EFAST},
};
use crate::domain::{SecretValue, bhpan::BhpanRootKind};
use crate::error::{Result, UbaaError};
use crate::ports::HttpMethod;
use crate::runtime::ClientRuntime;
use serde_json::json;

pub(crate) async fn roots(
    runtime: &mut ClientRuntime,
    token: &SecretValue,
    kind: BhpanRootKind,
) -> Result<Vec<parse::Item>> {
    let mut url = url::Url::parse(&format!("{}{EFAST}/entry-doc-lib", wire::ORIGIN))
        .map_err(|_| parse::invalid())?;
    url.query_pairs_mut()
        .append_pair("sort", "doc_lib_name")
        .append_pair("direction", "asc");
    let category = match kind {
        BhpanRootKind::All => None,
        BhpanRootKind::Personal => Some("user_doc_lib"),
        BhpanRootKind::Shared => Some("shared_user_doc_lib"),
        BhpanRootKind::Department => Some("department_doc_lib"),
        BhpanRootKind::Group => Some("custom_doc_lib"),
    };
    if let Some(category) = category {
        url.query_pairs_mut().append_pair("type", category);
    }
    let path = &url.as_str()[wire::ORIGIN.len()..];
    parse::roots(&wire::api(runtime, token, HttpMethod::Get, path, None, None, false).await?)
}
pub(crate) async fn personal(
    runtime: &mut ClientRuntime,
    token: &SecretValue,
) -> Result<parse::Item> {
    let mut roots = parse::roots(
        &wire::api(
            runtime,
            token,
            HttpMethod::Get,
            &format!("{EFAST}/owned-doc-lib"),
            None,
            None,
            false,
        )
        .await?,
    )?;
    if roots.len() != 1 {
        return Err(UbaaError::upstream_changed(
            "云盘个人文档库必须恰好返回一项",
        ));
    }
    Ok(roots.remove(0))
}
pub(crate) async fn list(
    runtime: &mut ClientRuntime,
    token: &SecretValue,
    id: &str,
    recycle: bool,
) -> Result<Vec<parse::Item>> {
    let (path, body) = if recycle {
        (
            "recycle/list",
            json!({"by":"time","docid":id,"limit":100,"sort":"desc","start":0}),
        )
    } else {
        ("dir/list", json!({"by":"name","docid":id,"sort":"asc"}))
    };
    parse::directory(
        &wire::api(
            runtime,
            token,
            HttpMethod::Post,
            &format!("{EFAST}/{path}"),
            Some(body),
            None,
            false,
        )
        .await?,
    )
}
