//! 与 home.dart 对应的公开读结果规则，绝不生成学校写资格。
use super::projection::{join, parse_time, school_item};
use crate::{
    cache::{CachedBykcChosenCourse, CachedCgyyOrder, CachedSigninClass, CachedYgdkOverview},
    domain::agenda::{
        AgendaNavigation, AgendaTime, AgendaTiming, SchoolAgendaItem, SchoolAgendaStatus,
        YgdkAgendaSettings,
    },
    domain::{
        Exam, JudgeAssignmentSummary, JudgeSubmissionStatus, SpocAssignmentSummary,
        SpocSubmissionStatus, Week,
    },
};
use chrono::{Datelike, Duration, NaiveDate};

pub(super) fn bykc(v: &CachedBykcChosenCourse, now: AgendaTime) -> Option<SchoolAgendaItem> {
    if v.course_id <= 0 {
        return None;
    }
    let start = parse_time(v.course_start_date.as_deref(), None);
    let end = parse_time(v.course_end_date.as_deref(), None);
    if start.is_none() && end.is_none() {
        return None;
    }
    let mut item = school_item(
        "bykc",
        v.course_id.to_string(),
        &v.course_name,
        AgendaTiming::Period { start, end },
        SchoolAgendaStatus::Bykc {
            checkin: v.checkin,
            pass: v.pass,
        },
        AgendaNavigation::Bykc {
            course_id: v.course_id,
        },
    );
    item.subtitle = join(
        &[v.course_teacher.as_deref(), v.course_position.as_deref()],
        "我的课程",
        " · ",
    );
    item.location.clone_from(&v.course_position);
    item.status_label = if start.is_some_and(|t| t <= now) {
        "进行中"
    } else {
        "即将开始"
    }
    .into();
    item.home_todo = end.is_none_or(|t| t >= now);
    Some(item)
}
pub(super) fn spoc(v: &SpocAssignmentSummary, now: AgendaTime) -> Option<SchoolAgendaItem> {
    if v.assignment_id.trim().is_empty() {
        return None;
    }
    let due = parse_time(v.due_time.as_deref(), None)?;
    let start = parse_time(v.start_time.as_deref(), None);
    let mut item = school_item(
        "spoc",
        v.assignment_id.clone(),
        &v.title,
        AgendaTiming::Deadline(due),
        SchoolAgendaStatus::Spoc {
            status: v.submission_status,
            text: v.submission_status_text.clone(),
        },
        AgendaNavigation::Spoc {
            assignment_id: v.assignment_id.clone(),
        },
    );
    item.subtitle = join(
        &[Some(&v.course_name), v.teacher_name.as_deref()],
        "SPOC 作业",
        " · ",
    );
    item.status_label = if v.submission_status == SpocSubmissionStatus::Unsubmitted {
        "待提交".into()
    } else {
        v.submission_status_text.clone()
    };
    item.home_todo = v.submission_status == SpocSubmissionStatus::Unsubmitted
        && start.is_none_or(|t| t <= now)
        && due > now;
    Some(item)
}
pub(super) fn judge(v: &JudgeAssignmentSummary, now: AgendaTime) -> Option<SchoolAgendaItem> {
    if v.course_id.trim().is_empty() || v.assignment_id.trim().is_empty() {
        return None;
    }
    let due = parse_time(v.due_time.as_deref(), None)?;
    let mut item = school_item(
        "judge",
        serde_json::to_string(&(&v.course_id, &v.assignment_id)).ok()?,
        &v.title,
        AgendaTiming::Deadline(due),
        SchoolAgendaStatus::Judge {
            status: v.submission_status,
            text: v.submission_status_text.clone(),
        },
        AgendaNavigation::Judge {
            course_id: v.course_id.clone(),
            assignment_id: v.assignment_id.clone(),
        },
    );
    item.subtitle = join(&[Some(&v.course_name)], "希冀作业", " · ");
    item.status_label = match v.submission_status {
        JudgeSubmissionStatus::Partial => "待完成".into(),
        JudgeSubmissionStatus::Unsubmitted => "待提交".into(),
        _ => v.submission_status_text.clone(),
    };
    item.home_todo = matches!(
        v.submission_status,
        JudgeSubmissionStatus::Unsubmitted | JudgeSubmissionStatus::Partial
    ) && due > now;
    Some(item)
}
pub(super) fn cgyy(v: &CachedCgyyOrder, now: AgendaTime) -> Option<SchoolAgendaItem> {
    if v.id <= 0 {
        return None;
    }
    let start = parse_time(v.reservation_start_date.as_deref(), None);
    let end = parse_time(v.reservation_end_date.as_deref(), None);
    if start.is_none() && end.is_none() {
        return None;
    }
    let title = join(
        &[
            v.venue_name.as_deref(),
            v.venue_space_name.as_deref().or(v.site_name.as_deref()),
        ],
        "研讨室预约",
        " / ",
    );
    let mut item = school_item(
        "cgyy",
        v.id.to_string(),
        &title,
        AgendaTiming::Period { start, end },
        SchoolAgendaStatus::Cgyy {
            order_status: v.order_status,
            check_status: v.check_status,
        },
        AgendaNavigation::Cgyy { order_id: v.id },
    );
    item.location = Some(title);
    item.subtitle = join(
        &[v.theme.as_deref(), v.purpose_type_name.as_deref()],
        "我的预约",
        " · ",
    );
    item.status_label = if start.is_some_and(|t| t <= now) {
        "使用中"
    } else {
        "待使用"
    }
    .into();
    item.home_todo = v.check_status.unwrap_or(0) >= 0
        && v.order_status != Some(2)
        && end.is_none_or(|t| t > now);
    Some(item)
}
pub(super) fn signin(
    v: &CachedSigninClass,
    date: NaiveDate,
    now: AgendaTime,
) -> Option<SchoolAgendaItem> {
    if v.course_id.trim().is_empty() || date != now.datetime.date_naive() {
        return None;
    }
    let start = parse_time(Some(&v.class_begin_time), Some(date))?;
    let end = parse_time(Some(&v.class_end_time), Some(date))?;
    let mut item = school_item(
        "signin",
        v.course_id.clone(),
        &v.course_name,
        AgendaTiming::Period {
            start: Some(start),
            end: Some(end),
        },
        SchoolAgendaStatus::Signin {
            sign_status: v.sign_status,
        },
        AgendaNavigation::Signin {
            course_id: v.course_id.clone(),
            date,
        },
    );
    item.subtitle = "课程签到".into();
    // 持久读永远没有新鲜操作资格；保留首页离线状态文案。
    item.status_label = "状态待更新".into();
    item.home_todo = v.sign_status == Some(0)
        && now < end
        && now.datetime >= start.datetime - Duration::minutes(10);
    Some(item)
}
pub(super) fn exam(v: &Exam, term: &str, now: AgendaTime) -> Option<SchoolAgendaItem> {
    static EXAM_END: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| {
        regex::Regex::new(r"^[0-9]{2}:[0-9]{2}(?::[0-9]{2}(?:\.[0-9]{1,9})?)?$")
            .expect("固定考试结束格式")
    });
    let raw_date = v.exam_date.as_deref()?.split(' ').next()?;
    let date = super::projection::parse_date(raw_date)?;
    let start = parse_time(v.start_time.as_deref(), Some(date));
    let end = parse_time(v.end_time.as_deref(), Some(date));
    let fallback = format!("{raw_date} 23:59");
    // isFinishedAt 接受两位钟点的小数秒；展示端点仍沿 _parseHomeTime。
    let finished_at = v
        .end_time
        .as_deref()
        .filter(|raw| EXAM_END.is_match(raw))
        .and_then(|raw| parse_time(Some(&format!("{raw_date} {raw}")), None))
        .or_else(|| parse_time(Some(&fallback), None))?;
    // task_id 是现有公开任务标识；沿 Dart 组合日期、开始时间区分考试发生。
    let identity = v
        .task_id
        .as_deref()
        .or(v.course_no.as_deref())
        .unwrap_or(&v.course_name);
    let key = serde_json::to_string(&(term, identity, &v.exam_date, &v.start_time)).ok()?;
    let timing = if start.is_none() && end.is_none() {
        AgendaTiming::AllDay {
            from: date,
            to: date.succ_opt()?,
        }
    } else {
        AgendaTiming::Period { start, end }
    };
    let mut item = school_item(
        "exam",
        key,
        &v.course_name,
        timing,
        SchoolAgendaStatus::Exam {
            status: v.exam_status,
        },
        AgendaNavigation::Exam {
            term: term.into(),
            task_id: v.task_id.clone(),
            course_no: v.course_no.clone(),
            course_name: v.course_name.clone(),
            date,
            start_time: v.start_time.clone(),
        },
    );
    let seat = v
        .exam_seat_no
        .as_ref()
        .filter(|s| !s.trim().is_empty())
        .map(|s| format!("座位 {s}"));
    item.subtitle = join(
        &[v.exam_place.as_deref(), seat.as_deref()],
        "考场待定",
        " · ",
    );
    item.location.clone_from(&v.exam_place);
    item.sort_time = Some(start.unwrap_or_else(|| crate::domain::agenda::campus_midnight(date)));
    item.status_label = if start.is_some_and(|t| t <= now) {
        "考试中"
    } else {
        "待考试"
    }
    .into();
    item.home_todo = now <= finished_at;
    Some(item)
}
pub(super) fn ygdk(
    v: &CachedYgdkOverview,
    week: &Week,
    now: AgendaTime,
    settings: YgdkAgendaSettings,
) -> Option<SchoolAgendaItem> {
    if !week.cur_week
        || week.term.trim().is_empty()
        || !(11..=14).contains(&week.serial_number)
        || !settings.enabled
        || settings.week_done
        || settings.term_done
        || v.summary.week_count.is_none_or(|n| n >= 4)
        || v.summary.term_count >= 16
    {
        return None;
    }
    let sunday = now
        .datetime
        .date_naive()
        .checked_add_signed(Duration::days(
            7 - i64::from(now.datetime.weekday().number_from_monday()),
        ))?;
    let due = parse_time(Some("23:59:59"), Some(sunday))?;
    let mut item = school_item(
        "ygdk",
        serde_json::to_string(&(&week.term, week.serial_number)).ok()?,
        "本周阳光打卡未达标",
        AgendaTiming::Deadline(due),
        SchoolAgendaStatus::Ygdk {
            week_count: v.summary.week_count,
            term_count: v.summary.term_count,
        },
        AgendaNavigation::Ygdk,
    );
    item.subtitle = format!("本周已打卡 {} / 4 次", v.summary.week_count?);
    item.status_label = "待打卡".into();
    item.home_todo = true;
    Some(item)
}
