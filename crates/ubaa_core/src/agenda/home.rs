//! 首页复用学校投影，不读取学校或业务缓存，也不伪造缓存观察时间。
use super::{AgendaStore, SchoolAgendaContext, projection, school};
use crate::{
    cache::{
        CacheError, CacheResult, CachedBykcChosenCourse, CachedCgyyOrder, CachedSemesterSchedule,
        CachedSigninClass, CachedYgdkOverview,
    },
    domain::agenda::{AgendaEntry, AgendaEntryItem, AgendaTime, AgendaTiming, SchoolAgendaOverlay},
    domain::{
        Exam, JudgeAssignmentSummary, JudgeSubmissionStatus, SpocAssignmentSummary,
        SpocSubmissionStatus, Week,
    },
};
use chrono::NaiveDate;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug)]
pub enum HomeAgendaRead {
    Bykc(Vec<CachedBykcChosenCourse>),
    Spoc(Vec<SpocAssignmentSummary>),
    Judge(Vec<JudgeAssignmentSummary>),
    Cgyy(Vec<CachedCgyyOrder>),
    Signin {
        date: NaiveDate,
        fresh: bool,
        classes: Vec<CachedSigninClass>,
    },
    Exam {
        term: String,
        exams: Vec<Exam>,
    },
    Ygdk(CachedYgdkOverview),
}
/// 将当次已取得的公开读结果投影为首页待办。输入没有学校写资格或缓存时间。
/// 可选日程库仅用于同账号本地覆盖，宿主负责账号与读取代次核对。
///
/// # Errors
/// 校园时间非法、数量超限或日程库不可读时返回本地错误。
pub fn project_home_agenda(
    reads: &[HomeAgendaRead],
    context: &SchoolAgendaContext,
    agenda: Option<&AgendaStore>,
) -> CacheResult<Vec<AgendaEntry>> {
    if !context.now.valid() {
        return Err(CacheError::InvalidInput);
    }
    let now = context.now;
    let mut items = Vec::new();
    let mut reopened = BTreeSet::new();
    for read in reads {
        match read {
            HomeAgendaRead::Bykc(v) => items.extend(v.iter().filter_map(|v| school::bykc(v, now))),
            HomeAgendaRead::Spoc(v) => {
                for v in v {
                    let mut pending = v.clone();
                    pending.submission_status = SpocSubmissionStatus::Unsubmitted;
                    if let Some(p) = school::spoc(&pending, now).filter(|p| p.home_todo) {
                        reopened.insert((p.key.source, p.key.upstream_id));
                    }
                    items.extend(school::spoc(v, now));
                }
            }
            HomeAgendaRead::Judge(v) => {
                for v in v {
                    let mut pending = v.clone();
                    pending.submission_status = JudgeSubmissionStatus::Unsubmitted;
                    if let Some(p) = school::judge(&pending, now).filter(|p| p.home_todo) {
                        reopened.insert((p.key.source, p.key.upstream_id));
                    }
                    items.extend(school::judge(v, now));
                }
            }
            HomeAgendaRead::Cgyy(v) => items.extend(v.iter().filter_map(|v| school::cgyy(v, now))),
            HomeAgendaRead::Signin {
                date,
                classes,
                fresh,
            } => items.extend(classes.iter().filter_map(|v| school::signin(v, *date, now)).map(|mut item| {
                if *fresh { item.status_label = if matches!(&item.timing, AgendaTiming::Period { start: Some(start), .. } if now < *start) { "即将签到" } else { "待签到" }.into(); }
                item
            })),
            HomeAgendaRead::Exam { term, exams } => {
                items.extend(exams.iter().filter_map(|v| school::exam(v, term, now)));
            }
            HomeAgendaRead::Ygdk(v) => {
                if let Some(week) = current_week(context.current_week.as_ref(), now) {
                    items.extend(school::ygdk(v, &week, now, context.ygdk));
                }
            }
        }
    }
    projection::remove_ambiguous_duplicates(&mut items, &mut BTreeMap::new());
    if items.len() > usize::from(u16::MAX) {
        return Err(CacheError::Capacity);
    }
    // 不受输入逐组到达顺序影响，同刻仍按既有来源、原响应顺序排列。
    items.sort_by_key(|v| match v.key.source.as_str() {
        "bykc" => 0,
        "spoc" => 1,
        "judge" => 2,
        "cgyy" => 3,
        "signin" => 4,
        "exam" => 5,
        _ => 6,
    });
    items.sort_by_key(|v| v.sort_time);
    let merge = |overlays: &BTreeMap<String, SchoolAgendaOverlay>| {
        let mut rows = Vec::new();
        for mut item in items {
            let key = super::operations::overlay_key(&item.key)?;
            let overlay = overlays.get(&key).filter(|o| o.deleted_at.is_none());
            if overlay.is_some_and(|o| o.hidden) {
                continue;
            }
            let explicit = overlay.filter(|o| o.completion_override);
            let pending = explicit.is_some_and(|o| o.completed_at.is_none());
            if explicit.is_some_and(|o| o.completed_at.is_some()) {
                continue;
            }
            if !(item.home_todo
                || pending
                    && reopened.contains(&(item.key.source.clone(), item.key.upstream_id.clone())))
            {
                continue;
            }
            if pending && item.upstream_status.completed() {
                item.status_label = "本地待办".into();
            }
            rows.push(AgendaEntry {
                completed: false,
                hidden: false,
                note: overlay.and_then(|o| o.note.clone()),
                item: AgendaEntryItem::School(item),
            });
        }
        Ok(rows)
    };
    if let Some(agenda) = agenda {
        agenda.access(true, false, |data| merge(&data.overlays))
    } else {
        merge(&BTreeMap::new())
    }
}

fn current_week(week: Option<&Week>, now: AgendaTime) -> Option<Week> {
    let week = week?;
    let weeks = CachedSemesterSchedule::normalized_weeks(&week.term, vec![week.clone()]).ok()?;
    weeks.into_iter().find(|w| {
        projection::parse_date(&w.start_date).is_some_and(|d| d <= now.datetime.date_naive())
            && projection::parse_date(&w.end_date).is_some_and(|d| now.datetime.date_naive() <= d)
    })
}
