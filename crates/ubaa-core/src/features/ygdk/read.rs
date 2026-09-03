//! 阳光打卡分类、项目、统计、学期概览与记录查询。

use crate::domain::{YgdkOverview, YgdkRecordsPage};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;

use super::auth::ensure_login;
use super::http::{post, post_with_query};
use super::parser::{
    classifies_fallback, error, integer, list, parse_envelope, parse_overview, parse_records,
    string,
};

const EMPTY_SUCCESS_ENVELOPE: &str = r#"{"code":1,"result":{}}"#;

/// 查询阳光打卡概览，按旧版顺序组合分类、项目、统计和学期接口。
pub(crate) async fn get_overview(runtime: &mut ClientRuntime) -> Result<YgdkOverview> {
    match get_overview_once(runtime).await {
        Err(error) if error.code == ErrorCode::AuthenticationRequired => {
            runtime.feature_state().ygdk.clear();
            get_overview_once(runtime).await
        }
        result => result,
    }
}

async fn get_overview_once(runtime: &mut ClientRuntime) -> Result<YgdkOverview> {
    let credential = ensure_login(runtime).await?;
    let classify = post(
        runtime,
        "/api/Front/Clockin/Classify/getList",
        &credential,
        &[],
    )
    .await?;
    let classifies = parse_envelope(&classify)?;
    let selected = classifies
        .as_object()
        .and_then(|v| {
            list(v, "list").into_iter().find_map(|v| {
                let o = v.as_object()?.clone();
                (string(&o, "name").is_some_and(|n| n.contains("体育"))).then_some(o)
            })
        })
        .or_else(|| classifies_fallback(&classifies))
        .ok_or_else(|| error("未获取到阳光打卡分类"))?;
    let classify_id =
        integer(&selected, "classify_id").ok_or_else(|| error("阳光打卡分类缺少标识"))?;
    let query = [
        ("page", "1".to_owned()),
        ("limit", "1000".to_owned()),
        ("classify_id", classify_id.to_string()),
    ];
    let items = post_with_query(
        runtime,
        "/api/Front/Clockin/Item/getList",
        &credential,
        &query,
    )
    .await?;
    let count = optional_success_response(
        post(
            runtime,
            "/api/Front/Clockin/Clockin/getCount",
            &credential,
            &[
                ("classify_id", classify_id.to_string()),
                ("user_id", credential.uid.to_string()),
            ],
        )
        .await,
    );
    let term = optional_success_response(
        post(runtime, "/api/Front/Clockin/Term/get", &credential, &[]).await,
    );
    parse_overview(&classify, &items, &count, &term)
}

fn optional_success_response(response: Result<String>) -> String {
    match response {
        Ok(body) if parse_envelope(&body).is_ok() => body,
        _ => EMPTY_SUCCESS_ENVELOPE.to_owned(),
    }
}

/// 查询阳光打卡历史记录。
pub(crate) async fn get_records(
    runtime: &mut ClientRuntime,
    page: i32,
    size: i32,
) -> Result<YgdkRecordsPage> {
    if page <= 0 || size <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "分页参数无效",
        ));
    }
    let credential = ensure_login(runtime).await?;
    let overview = get_overview(runtime).await?;
    let params = [
        ("page", page.to_string()),
        ("limit", size.to_string()),
        ("classify_id", overview.classify_id.to_string()),
        ("user_id", credential.uid.to_string()),
    ];
    let body = post_with_query(
        runtime,
        "/api/Front/Clockin/Clockin/getList",
        &credential,
        &params,
    )
    .await?;
    parse_records(&body, &overview.items, page, size)
}
