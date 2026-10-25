//! iHome 来源已核对的读取与单次切换操作。
mod auth;
pub(crate) mod parser;
#[cfg(test)]
mod tests;
use crate::domain::{
    IhomeAppeal, IhomeConfig, IhomeFilter, IhomeNotice, IhomePage, IhomeQuery, IhomeReaction,
    IhomeScope,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::ports::HttpRequest;
use crate::runtime::ClientRuntime;
use parser::invalid;
const BASE: &str = "https://i.buaa.edu.cn/api";
fn input_error() -> UbaaError {
    UbaaError::new(
        ErrorCode::InvalidInput,
        ErrorKind::Input,
        false,
        "iHome 查询参数无效",
    )
}
fn valid_id(id: i64) -> Result<()> {
    if id <= 0 { Err(input_error()) } else { Ok(()) }
}
pub(super) fn page_url(query: &IhomeQuery) -> Result<String> {
    if query.page < 1
        || !(1..=100).contains(&query.limit)
        || query.keyword.chars().count() > 200
        || query.category_id.is_some_and(|id| id <= 0)
    {
        return Err(input_error());
    }
    let path = match query.scope {
        IhomeScope::Public => "/appeal",
        IhomeScope::Mine => "/appeal/my_appreal",
        IhomeScope::Followed => "/appeal/my_follow",
        IhomeScope::Appraised => "/appraise/my_appraise",
    };
    let mut url = url::Url::parse(&format!("{BASE}{path}")).map_err(|_| invalid())?;
    {
        let mut p = url.query_pairs_mut();
        p.append_pair("limit", &query.limit.to_string())
            .append_pair("page", &query.page.to_string());
        if query.scope == IhomeScope::Public {
            if !query.keyword.trim().is_empty() {
                p.append_pair("keyword", query.keyword.trim());
            }
            if let Some(id) = query.category_id {
                p.append_pair("sqlb_id", &id.to_string());
            }
        }
        if matches!(query.scope, IhomeScope::Public | IhomeScope::Mine) {
            match query.filter {
                IhomeFilter::All => {}
                IhomeFilter::Newest => {
                    p.append_pair("publish_time", "1");
                }
                IhomeFilter::Oldest if query.scope == IhomeScope::Public => {
                    p.append_pair("publish_time", "0");
                }
                IhomeFilter::ReplyTime if query.scope == IhomeScope::Mine => {
                    p.append_pair("reply_time", "0");
                }
                IhomeFilter::Replied | IhomeFilter::Unreplied => {
                    p.append_pair(
                        if query.scope == IhomeScope::Mine {
                            "is_reply"
                        } else {
                            "reply"
                        },
                        if query.filter == IhomeFilter::Replied {
                            "1"
                        } else {
                            "0"
                        },
                    );
                }
                _ => return Err(input_error()),
            }
        }
    }
    Ok(url.to_string())
}
async fn read(runtime: &mut ClientRuntime, url: &str) -> Result<serde_json::Value> {
    for attempt in 0..2 {
        let token = auth::ensure_token(runtime).await?;
        let generation = runtime.feature_state().ihome.snapshot().0;
        let expected = runtime.url(url)?;
        let request =
            HttpRequest::get(&expected).with_header("Authorization", format!("Bearer {token}"));
        let response = runtime
            .request_with_pre_send_check(request, |r| auth::check_generation(r, generation))
            .await?;
        auth::check_generation(runtime, generation)?;
        if response.final_url != expected {
            return Err(invalid());
        }
        if response.status == 401 {
            runtime.feature_state().ihome.clear();
            if attempt == 0 {
                continue;
            }
        }
        if !(200..300).contains(&response.status) {
            return Err(UbaaError::new(
                ErrorCode::UpstreamUnavailable,
                ErrorKind::Upstream,
                false,
                "iHome 暂时不可用，请稍后重试",
            ));
        }
        return parser::envelope(&crate::features::body(&response));
    }
    Err(invalid())
}
pub(crate) async fn get_page(runtime: &mut ClientRuntime, query: &IhomeQuery) -> Result<IhomePage> {
    parser::page(&read(runtime, &page_url(query)?).await?, query.scope)
}
pub(crate) async fn get_detail(
    runtime: &mut ClientRuntime,
    id: i64,
    mine: bool,
) -> Result<IhomeAppeal> {
    valid_id(id)?;
    parser::appeal(
        &read(
            runtime,
            &format!(
                "{BASE}/appeal/{}{id}",
                if mine { "my_appreal/" } else { "" }
            ),
        )
        .await?,
    )
}
pub(crate) async fn get_config(runtime: &mut ClientRuntime) -> Result<IhomeConfig> {
    let settings = read(
        runtime,
        &format!("{BASE}/general_set_more?key%5B%5D=fabulous&key%5B%5D=fabulous_show"),
    )
    .await?;
    let types = read(runtime, &format!("{BASE}/mobile/types?type_mark=SQLB")).await?;
    parser::config(&settings, &types)
}
pub(crate) async fn get_notices(runtime: &mut ClientRuntime) -> Result<Vec<IhomeNotice>> {
    parser::notices(&read(runtime, &format!("{BASE}/notice")).await?)
}
pub(crate) async fn get_notice(runtime: &mut ClientRuntime, id: i64) -> Result<IhomeNotice> {
    valid_id(id)?;
    parser::notice(&read(runtime, &format!("{BASE}/notice?id={id}")).await?)
}
pub(crate) async fn set_reaction(
    runtime: &mut ClientRuntime,
    id: i64,
    reaction: IhomeReaction,
    enabled: bool,
) -> Result<IhomeAppeal> {
    let state = runtime.feature_state();
    let _guard = state.ihome.mutation.lock().await;
    let before = get_detail(runtime, id, false).await?;
    let current = |v: &IhomeAppeal| {
        if reaction == IhomeReaction::Follow {
            v.is_followed
        } else {
            v.is_supported
        }
    };
    if current(&before) == Some(enabled) {
        return Ok(before);
    }
    if current(&before).is_none() {
        return Err(invalid());
    }
    if reaction == IhomeReaction::Support && !get_config(runtime).await?.support_enabled {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "平台当前未开放支持功能",
        ));
    }
    let token = auth::ensure_token(runtime).await?;
    let generation = state.ihome.snapshot().0;
    let path = if reaction == IhomeReaction::Follow {
        "appeal_follow"
    } else {
        "appeal/appeal_praise"
    };
    let mut request = HttpRequest::post(
        runtime.url(&format!("{BASE}/{path}/{id}"))?,
        if reaction == IhomeReaction::Follow {
            b"{}".to_vec()
        } else {
            vec![]
        },
    )
    .with_header("Authorization", format!("Bearer {token}"));
    if reaction == IhomeReaction::Follow {
        request = request.with_header("Content-Type", "application/json");
    }
    // 切换仅提交一次；所有提交后失败均通过只读回查确认，不自动反向重放。
    let sent = runtime
        .request_non_idempotent_with_pre_send_check(request, |r| {
            auth::check_generation(r, generation)
        })
        .await;
    if let Err(error) = &sent
        && error.code != ErrorCode::OutcomeUnknown
    {
        return Err(error.clone());
    }
    if let Ok(response) = &sent
        && response.status == 401
    {
        state.ihome.clear();
    }
    match get_detail(runtime, id, false).await {
        Ok(after) if current(&after) == Some(enabled) => Ok(after),
        _ => Err(UbaaError::new(
            ErrorCode::OutcomeUnknown,
            ErrorKind::Upstream,
            false,
            "操作结果未确认，请刷新诉求详情后核对",
        )),
    }
}
