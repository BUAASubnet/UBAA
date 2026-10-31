//! 仅转换已解析的 typed 读字段，不读取缓存、凭据或学校网络。
use super::{
    BridgeAgendaStore,
    convert::error,
    models::{BridgeAgendaError, BridgeAgendaTime},
    projection,
    school::{BridgeAgendaEntry, BridgeAgendaSubmission},
    task,
};
use crate::api::read::BridgeWeek;
use ubaa_core::facade as core;
#[derive(Clone, Debug)]
pub struct BridgeHomeAgendaInput {
    pub bykc: Vec<BridgeHomeBykc>,
    pub spoc: Vec<BridgeHomeSpoc>,
    pub judge: Vec<BridgeHomeJudge>,
    pub cgyy: Vec<BridgeHomeCgyy>,
    pub signin: Vec<BridgeHomeSignin>,
    pub exam: Vec<BridgeHomeExam>,
    pub ygdk: Vec<BridgeHomeYgdk>,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeBykc {
    pub course_id: i64,
    pub title: String,
    pub teacher: Option<String>,
    pub place: Option<String>,
    pub start: Option<String>,
    pub end: Option<String>,
    pub checkin: Option<i32>,
    pub pass: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeSpoc {
    pub assignment_id: String,
    pub title: String,
    pub course_name: String,
    pub teacher: Option<String>,
    pub start: Option<String>,
    pub due: Option<String>,
    pub status: BridgeAgendaSubmission,
    pub status_text: String,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeJudge {
    pub course_id: String,
    pub assignment_id: String,
    pub title: String,
    pub course_name: String,
    pub due: Option<String>,
    pub status: BridgeAgendaSubmission,
    pub status_text: String,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeCgyy {
    pub order_id: i32,
    pub venue: Option<String>,
    pub space: Option<String>,
    pub site: Option<String>,
    pub theme: Option<String>,
    pub purpose: Option<String>,
    pub start: Option<String>,
    pub end: Option<String>,
    pub order_status: Option<i32>,
    pub check_status: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeSignin {
    pub fresh: bool,
    pub date: String,
    pub course_id: String,
    pub title: String,
    pub start: String,
    pub end: String,
    pub sign_status: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeExam {
    pub term: String,
    pub title: String,
    pub task_id: Option<String>,
    pub course_no: Option<String>,
    pub date: Option<String>,
    pub start: Option<String>,
    pub end: Option<String>,
    pub place: Option<String>,
    pub seat: Option<String>,
    pub status: Option<i32>,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeYgdk {
    pub week_count: Option<i32>,
    pub term_count: i32,
}
#[derive(Clone, Debug)]
pub struct BridgeHomeAgendaContext {
    pub now: BridgeAgendaTime,
    pub current_week: Option<BridgeWeek>,
    pub ygdk_enabled: bool,
    pub ygdk_week_done: bool,
    pub ygdk_term_done: bool,
}
fn inputs(values: BridgeHomeAgendaInput) -> Result<Vec<core::HomeAgendaRead>, BridgeAgendaError> {
    let mut result = Vec::new();
    result.extend(values.bykc.into_iter().map(core::HomeAgendaRead::from));
    result.extend(values.spoc.into_iter().map(core::HomeAgendaRead::from));
    result.extend(values.judge.into_iter().map(core::HomeAgendaRead::from));
    result.extend(values.cgyy.into_iter().map(core::HomeAgendaRead::from));
    result.extend(values.exam.into_iter().map(core::HomeAgendaRead::from));
    result.extend(values.ygdk.into_iter().map(core::HomeAgendaRead::from));
    result.extend(
        values
            .signin
            .into_iter()
            .map(TryInto::try_into)
            .collect::<Result<Vec<_>, BridgeAgendaError>>()?,
    );
    Ok(result)
}
fn context(v: BridgeHomeAgendaContext) -> Result<core::SchoolAgendaContext, BridgeAgendaError> {
    Ok(core::SchoolAgendaContext {
        now: v.now.try_into()?,
        current_week: v.current_week.map(|w| core::Week {
            start_date: w.start_date,
            end_date: w.end_date,
            term: w.term,
            cur_week: w.cur_week,
            serial_number: w.serial_number,
            name: w.name,
        }),
        ygdk: core::YgdkAgendaSettings {
            enabled: v.ygdk_enabled,
            week_done: v.ygdk_week_done,
            term_done: v.ygdk_term_done,
        },
    })
}
fn project(
    values: BridgeHomeAgendaInput,
    ctx: BridgeHomeAgendaContext,
    store: Option<&core::AgendaStore>,
) -> Result<Vec<BridgeAgendaEntry>, BridgeAgendaError> {
    let context = context(ctx)?;
    Ok(core::project_home_agenda(&inputs(values)?, &context, store)
        .map_err(error)?
        .into_iter()
        .map(|e| projection::entry(e, context.now))
        .collect())
}
/// 无日程句柄时立即投影在线或离线读结果，不等待安全材料。
///
/// # Errors
/// 校园时间、日期非法或结果超限时返回本地错误。
pub async fn agenda_project_home(
    values: BridgeHomeAgendaInput,
    context: BridgeHomeAgendaContext,
) -> Result<Vec<BridgeAgendaEntry>, BridgeAgendaError> {
    task(move || project(values, context, None)).await
}
impl BridgeAgendaStore {
    /// 用同账号日程覆盖合并已取得读结果，不重新读取学校缓存。
    ///
    /// # Errors
    /// 输入非法、结果超限或日程不可读时返回独立日程错误。
    pub async fn project_home(
        &self,
        values: BridgeHomeAgendaInput,
        context: BridgeHomeAgendaContext,
    ) -> Result<Vec<BridgeAgendaEntry>, BridgeAgendaError> {
        let store = self.store.clone();
        task(move || project(values, context, Some(&store))).await
    }
}
