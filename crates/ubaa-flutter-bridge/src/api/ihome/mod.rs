//! iHome 的类型化绑定，白名单 DTO 与固定路线操作。
#![allow(clippy::missing_errors_doc, clippy::needless_pass_by_value)]
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeRouteDecision, catch_panic,
    disposed_error, map_route,
};
use ubaa_core::facade as domain;
#[derive(Clone, Copy, Debug)]
pub enum BridgeIhomeScope {
    Public,
    Mine,
    Followed,
    Appraised,
}
impl From<BridgeIhomeScope> for domain::IhomeScope {
    fn from(v: BridgeIhomeScope) -> Self {
        match v {
            BridgeIhomeScope::Public => Self::Public,
            BridgeIhomeScope::Mine => Self::Mine,
            BridgeIhomeScope::Followed => Self::Followed,
            BridgeIhomeScope::Appraised => Self::Appraised,
        }
    }
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeIhomeFilter {
    All,
    Newest,
    Oldest,
    Replied,
    Unreplied,
    ReplyTime,
}
impl From<BridgeIhomeFilter> for domain::IhomeFilter {
    fn from(v: BridgeIhomeFilter) -> Self {
        match v {
            BridgeIhomeFilter::All => Self::All,
            BridgeIhomeFilter::Newest => Self::Newest,
            BridgeIhomeFilter::Oldest => Self::Oldest,
            BridgeIhomeFilter::Replied => Self::Replied,
            BridgeIhomeFilter::Unreplied => Self::Unreplied,
            BridgeIhomeFilter::ReplyTime => Self::ReplyTime,
        }
    }
}
#[derive(Clone, Copy, Debug)]
pub enum BridgeIhomeReaction {
    Follow,
    Support,
}
impl From<BridgeIhomeReaction> for domain::IhomeReaction {
    fn from(v: BridgeIhomeReaction) -> Self {
        match v {
            BridgeIhomeReaction::Follow => Self::Follow,
            BridgeIhomeReaction::Support => Self::Support,
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeQuery {
    pub scope: BridgeIhomeScope,
    pub page: i32,
    pub limit: i32,
    pub keyword: String,
    pub filter: BridgeIhomeFilter,
    pub category_id: Option<i64>,
}
impl From<BridgeIhomeQuery> for domain::IhomeQuery {
    fn from(v: BridgeIhomeQuery) -> Self {
        Self {
            scope: v.scope.into(),
            page: v.page,
            limit: v.limit,
            keyword: v.keyword,
            filter: v.filter.into(),
            category_id: v.category_id,
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomePage {
    pub entries: Vec<BridgeIhomeEntry>,
    pub page: i32,
    pub last_page: i32,
    pub total: i32,
}
impl From<domain::IhomePage> for BridgeIhomePage {
    fn from(v: domain::IhomePage) -> Self {
        Self {
            entries: v.entries.into_iter().map(Into::into).collect(),
            page: v.page,
            last_page: v.last_page,
            total: v.total,
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeEntry {
    pub appeal: BridgeIhomeAppeal,
    pub evaluation: Option<BridgeIhomeEvaluation>,
}
impl From<domain::IhomeEntry> for BridgeIhomeEntry {
    fn from(v: domain::IhomeEntry) -> Self {
        Self {
            appeal: v.appeal.into(),
            evaluation: v.evaluation.map(Into::into),
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeAppeal {
    pub id: i64,
    pub content: String,
    pub status: String,
    pub category: String,
    pub published_at: String,
    pub departments: Vec<String>,
    pub is_mine: bool,
    pub is_followed: Option<bool>,
    pub is_supported: Option<bool>,
    pub follow_count: Option<i32>,
    pub support_count: Option<i32>,
    pub replies: Vec<BridgeIhomeReply>,
    pub evaluations: Vec<BridgeIhomeEvaluation>,
    pub history: Vec<BridgeIhomeHistory>,
}
impl From<domain::IhomeAppeal> for BridgeIhomeAppeal {
    fn from(v: domain::IhomeAppeal) -> Self {
        Self {
            id: v.id,
            content: v.content,
            status: v.status,
            category: v.category,
            published_at: v.published_at,
            departments: v.departments,
            is_mine: v.is_mine,
            is_followed: v.is_followed,
            is_supported: v.is_supported,
            follow_count: v.follow_count,
            support_count: v.support_count,
            replies: v.replies.into_iter().map(Into::into).collect(),
            evaluations: v.evaluations.into_iter().map(Into::into).collect(),
            history: v.history.into_iter().map(Into::into).collect(),
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeReply {
    pub content: String,
    pub department: String,
    pub created_at: String,
}
impl From<domain::IhomeReply> for BridgeIhomeReply {
    fn from(v: domain::IhomeReply) -> Self {
        Self {
            content: v.content,
            department: v.department,
            created_at: v.created_at,
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeHistory {
    pub content: String,
    pub created_at: String,
}
impl From<domain::IhomeHistory> for BridgeIhomeHistory {
    fn from(v: domain::IhomeHistory) -> Self {
        Self {
            content: v.content,
            created_at: v.created_at,
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeEvaluation {
    pub id: i64,
    pub department: String,
    pub speed: i32,
    pub satisfaction: i32,
    pub degree: i32,
    pub content: String,
    pub created_at: String,
}
impl From<domain::IhomeEvaluation> for BridgeIhomeEvaluation {
    fn from(v: domain::IhomeEvaluation) -> Self {
        Self {
            id: v.id,
            department: v.department,
            speed: v.speed,
            satisfaction: v.satisfaction,
            degree: v.degree,
            content: v.content,
            created_at: v.created_at,
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeCategory {
    pub id: i64,
    pub name: String,
}
impl From<domain::IhomeCategory> for BridgeIhomeCategory {
    fn from(v: domain::IhomeCategory) -> Self {
        Self {
            id: v.id,
            name: v.name,
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeConfig {
    pub support_enabled: bool,
    pub support_label: String,
    pub categories: Vec<BridgeIhomeCategory>,
}
impl From<domain::IhomeConfig> for BridgeIhomeConfig {
    fn from(v: domain::IhomeConfig) -> Self {
        Self {
            support_enabled: v.support_enabled,
            support_label: v.support_label,
            categories: v.categories.into_iter().map(Into::into).collect(),
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeNotice {
    pub id: i64,
    pub title: String,
    pub content: String,
    pub date: String,
}
impl From<domain::IhomeNotice> for BridgeIhomeNotice {
    fn from(v: domain::IhomeNotice) -> Self {
        Self {
            id: v.id,
            title: v.title,
            content: v.content,
            date: v.date,
        }
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomePageResult {
    pub data: BridgeIhomePage,
    pub route: BridgeRouteDecision,
}
impl BridgeClient {
    pub async fn ihome_page(
        &self,
        query: BridgeIhomeQuery,
    ) -> Result<BridgeIhomePageResult, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .ihome_page(query.into())
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeIhomePageResult {
                data: value.data.into(),
                route: map_route(value.resolution),
            })
        })
        .await
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeDetailResult {
    pub data: BridgeIhomeAppeal,
    pub route: BridgeRouteDecision,
}
impl BridgeClient {
    pub async fn ihome_detail(
        &self,
        id: i64,
        mine: bool,
    ) -> Result<BridgeIhomeDetailResult, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .ihome_detail(id, mine)
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeIhomeDetailResult {
                data: value.data.into(),
                route: map_route(value.resolution),
            })
        })
        .await
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeConfigResult {
    pub data: BridgeIhomeConfig,
    pub route: BridgeRouteDecision,
}
impl BridgeClient {
    pub async fn ihome_config(&self) -> Result<BridgeIhomeConfigResult, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .ihome_config()
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeIhomeConfigResult {
                data: value.data.into(),
                route: map_route(value.resolution),
            })
        })
        .await
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeNoticesResult {
    pub data: Vec<BridgeIhomeNotice>,
    pub route: BridgeRouteDecision,
}
impl BridgeClient {
    pub async fn ihome_notices(&self) -> Result<BridgeIhomeNoticesResult, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .ihome_notices()
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeIhomeNoticesResult {
                data: value.data.into_iter().map(Into::into).collect(),
                route: map_route(value.resolution),
            })
        })
        .await
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeNoticeResult {
    pub data: BridgeIhomeNotice,
    pub route: BridgeRouteDecision,
}
impl BridgeClient {
    pub async fn ihome_notice(&self, id: i64) -> Result<BridgeIhomeNoticeResult, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            let value = client
                .ihome_notice(id)
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeIhomeNoticeResult {
                data: value.data.into(),
                route: map_route(value.resolution),
            })
        })
        .await
    }
}
#[derive(Clone, Debug)]
pub struct BridgeIhomeReactionResult {
    pub data: BridgeIhomeAppeal,
    pub route: BridgeRouteDecision,
}
impl BridgeClient {
    pub async fn ihome_set_reaction(
        &self,
        id: i64,
        reaction: BridgeIhomeReaction,
        enabled: bool,
        expected_route: BridgeConnectionMode,
    ) -> Result<BridgeIhomeReactionResult, BridgeError> {
        let mut observation = None;
        let result = catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            observation = Some(client.observe_write_boundary());
            let value = client
                .ihome_set_reaction(id, reaction.into(), enabled, expected_route.into())
                .await
                .map_err(BridgeError::from_routed)?;
            Ok(BridgeIhomeReactionResult {
                data: value.data.into(),
                route: map_route(value.resolution),
            })
        })
        .await;
        if let Err(error) = &result
            && error.code == super::client::BridgeErrorCode::InternalError
            && observation.is_some_and(|value| value.may_have_been_sent())
        {
            return Err(BridgeError::from_core(
                domain::UbaaError::new(
                    domain::ErrorCode::OutcomeUnknown,
                    domain::ErrorKind::Upstream,
                    false,
                    "操作结果未确认，请刷新诉求详情后核对",
                ),
                Some(expected_route),
            ));
        }
        result
    }
}
