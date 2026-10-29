//! 依冻结旧版先本科、失败再实际验证GSMIS；不跨Direct/WebVPN路线。
use super::graduate;
use crate::domain::{Term, TodayClass, Week, WeeklySchedule};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;
fn check_term(term: &str) -> Result<()> {
    if term.trim().is_empty() {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "学期不能为空",
        ));
    }
    Ok(())
}
pub(crate) async fn get_terms(runtime: &mut ClientRuntime) -> Result<Vec<Term>> {
    if !graduate::active(runtime)
        && let Ok(value) = super::get_terms_undergraduate(runtime).await
    {
        return Ok(value);
    }
    Ok(graduate::fetch(runtime, None).await?.terms())
}
pub(crate) async fn get_weeks(runtime: &mut ClientRuntime, term: &str) -> Result<Vec<Week>> {
    check_term(term)?;
    if !graduate::active(runtime)
        && let Ok(value) = super::get_weeks_undergraduate(runtime, term).await
    {
        return Ok(value);
    }
    graduate::fetch(runtime, Some(term))
        .await?
        .weeks(&crate::time::shanghai_date(std::time::SystemTime::now()))
}
pub(crate) async fn get_weeks_for_import(
    runtime: &mut ClientRuntime,
    term: &str,
) -> Result<Vec<Week>> {
    check_term(term)?;
    if !graduate::active(runtime)
        && let Ok(value) = super::get_weeks_for_import_undergraduate(runtime, term).await
    {
        return Ok(value);
    }
    graduate::fetch(runtime, Some(term))
        .await?
        .weeks(&crate::time::shanghai_date(std::time::SystemTime::now()))
}
pub(crate) async fn get_week(
    runtime: &mut ClientRuntime,
    term: &str,
    week: i32,
) -> Result<WeeklySchedule> {
    check_week(term, week)?;
    if !graduate::active(runtime)
        && let Ok(value) = super::get_week_undergraduate(runtime, term, week).await
    {
        return Ok(value);
    }
    graduate::fetch(runtime, Some(term)).await?.weekly(week)
}
pub(crate) async fn get_week_for_import(
    runtime: &mut ClientRuntime,
    term: &str,
    week: i32,
) -> Result<WeeklySchedule> {
    check_week(term, week)?;
    if !graduate::active(runtime)
        && let Ok(value) = super::get_week_for_import_undergraduate(runtime, term, week).await
    {
        return Ok(value);
    }
    graduate::fetch(runtime, Some(term)).await?.weekly(week)
}
fn check_week(term: &str, week: i32) -> Result<()> {
    check_term(term)?;
    if week <= 0 {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "周次必须为正数",
        ));
    }
    Ok(())
}
pub(crate) async fn get_today(runtime: &mut ClientRuntime) -> Result<Vec<TodayClass>> {
    get_today_for_date(
        runtime,
        &crate::time::shanghai_date(std::time::SystemTime::now()),
    )
    .await
}
pub(crate) async fn get_today_for_date(
    runtime: &mut ClientRuntime,
    date: &str,
) -> Result<Vec<TodayClass>> {
    if !graduate::active(runtime)
        && let Ok(value) = super::get_today_for_date_undergraduate(runtime, date).await
    {
        return Ok(value);
    }
    graduate::fetch(runtime, None).await?.today(date)
}
