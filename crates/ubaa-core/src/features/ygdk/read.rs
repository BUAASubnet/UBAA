//! 阳光打卡分类、项目、统计、学期概览与记录查询。

use crate::domain::{YgdkOverview, YgdkRecordsPage};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;

use super::auth::ensure_login;
use super::http::{ensure_active_credential, is_pre_send_credential_error, post, post_with_query};
use super::parser::{
    classifies_fallback, error, integer, list, parse_envelope, parse_overview, parse_records,
    string,
};

const EMPTY_SUCCESS_ENVELOPE: &str = r#"{"code":1,"result":{}}"#;

pub(crate) struct YgdkOverviewContext {
    pub(crate) overview: YgdkOverview,
    pub(crate) generation: u64,
    pub(crate) credential: super::YgdkCredential,
}

/// 查询阳光打卡概览，按旧版顺序组合分类、项目、统计和学期接口。
pub(crate) async fn get_overview(runtime: &mut ClientRuntime) -> Result<YgdkOverview> {
    get_overview_context(runtime)
        .await
        .map(|context| context.overview)
}

pub(crate) async fn get_overview_context(
    runtime: &mut ClientRuntime,
) -> Result<YgdkOverviewContext> {
    match get_overview_context_once(runtime).await {
        Err(error) if error.code == ErrorCode::AuthenticationRequired => {
            runtime.feature_state().ygdk.clear();
            get_overview_context_once(runtime).await
        }
        result => result,
    }
}

pub(crate) async fn get_overview_context_once(
    runtime: &mut ClientRuntime,
) -> Result<YgdkOverviewContext> {
    let credential = ensure_login(runtime).await?;
    let generation = runtime.feature_state().ygdk.generation();
    ensure_active_credential(runtime, generation, &credential)?;
    let classify = post(
        runtime,
        "/api/Front/Clockin/Classify/getList",
        &credential,
        generation,
        &[],
    )
    .await?;
    ensure_active_credential(runtime, generation, &credential)?;
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
        generation,
        &query,
    )
    .await?;
    ensure_active_credential(runtime, generation, &credential)?;
    parse_envelope(&items)?;
    let count = optional_success_response(
        post(
            runtime,
            "/api/Front/Clockin/Clockin/getCount",
            &credential,
            generation,
            &[
                ("classify_id", classify_id.to_string()),
                ("user_id", credential.uid.to_string()),
            ],
        )
        .await,
    )?;
    ensure_active_credential(runtime, generation, &credential)?;
    let term = optional_success_response(
        post(
            runtime,
            "/api/Front/Clockin/Term/get",
            &credential,
            generation,
            &[],
        )
        .await,
    )?;
    ensure_active_credential(runtime, generation, &credential)?;
    let overview = parse_overview(&classify, &items, &count, &term)?;
    Ok(YgdkOverviewContext {
        overview,
        generation,
        credential,
    })
}

fn optional_success_response(response: Result<String>) -> Result<String> {
    match response {
        Ok(body) => match parse_envelope(&body) {
            Ok(_) => Ok(body),
            Err(error) if error.code == ErrorCode::AuthenticationRequired => Err(error),
            Err(_) => Ok(EMPTY_SUCCESS_ENVELOPE.to_owned()),
        },
        Err(error)
            if error.code == ErrorCode::AuthenticationRequired
                || is_pre_send_credential_error(&error) =>
        {
            Err(error)
        }
        Err(_) => Ok(EMPTY_SUCCESS_ENVELOPE.to_owned()),
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
    let context = get_overview_context(runtime).await?;
    ensure_active_credential(runtime, context.generation, &context.credential)?;
    let params = [
        ("page", page.to_string()),
        ("limit", size.to_string()),
        ("classify_id", context.overview.classify_id.to_string()),
        ("user_id", context.credential.uid.to_string()),
    ];
    let body = post_with_query(
        runtime,
        "/api/Front/Clockin/Clockin/getList",
        &context.credential,
        context.generation,
        &params,
    )
    .await?;
    ensure_active_credential(runtime, context.generation, &context.credential)?;
    parse_records(&body, &context.overview.items, page, size)
}

#[cfg(test)]
mod tests {
    use super::optional_success_response;
    use crate::error::{ErrorCode, ErrorKind, UbaaError};

    #[test]
    fn 可选请求不得吞掉发送入口的代次或会话_guard_失败() {
        for (code, kind, retryable, message) in [
            (
                ErrorCode::AuthenticationRequired,
                ErrorKind::Authentication,
                false,
                "阳光打卡业务会话已变化，请重新读取并确认",
            ),
            (
                ErrorCode::InternalError,
                ErrorKind::Internal,
                true,
                "阳光打卡本地会话状态检查失败",
            ),
        ] {
            let original = UbaaError::new(code, kind, retryable, message);
            let error = optional_success_response(Err(original))
                .expect_err("guard 失败必须终止 overview 组合");
            assert_eq!(
                (
                    error.code,
                    error.kind,
                    error.retryable,
                    error.message.as_str()
                ),
                (code, kind, retryable, message)
            );
        }
    }
}
