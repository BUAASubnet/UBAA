use super::school::{
    BridgeAgendaEntry, BridgeAgendaFeature, BridgeAgendaNavigation, BridgeAgendaQueryResult,
    BridgeAgendaSubmission, BridgeAgendaTiming, BridgeAgendaTimingKind, BridgeAgendaUpstreamStatus,
    BridgeSchoolAgendaItem,
};
use ubaa_core::facade as core;
impl From<core::ReadonlyFeature> for BridgeAgendaFeature {
    fn from(v: core::ReadonlyFeature) -> Self {
        match v {
            core::ReadonlyFeature::Bykc => Self::Bykc,
            core::ReadonlyFeature::Spoc => Self::Spoc,
            core::ReadonlyFeature::Judge => Self::Judge,
            core::ReadonlyFeature::Cgyy => Self::Cgyy,
            core::ReadonlyFeature::Signin => Self::Signin,
            core::ReadonlyFeature::Exam => Self::Exam,
            core::ReadonlyFeature::Ygdk => Self::Ygdk,
            core::ReadonlyFeature::Schedule => Self::Schedule,
            _ => unreachable!("日程只包含八种已定义来源"),
        }
    }
}
impl From<core::AgendaTiming> for BridgeAgendaTiming {
    fn from(v: core::AgendaTiming) -> Self {
        let mut result = Self {
            kind: BridgeAgendaTimingKind::Undated,
            start: None,
            end: None,
            due: None,
            from: None,
            to: None,
        };
        match v {
            core::AgendaTiming::Period { start, end } => {
                result.kind = BridgeAgendaTimingKind::Period;
                result.start = start.map(Into::into);
                result.end = end.map(Into::into);
            }
            core::AgendaTiming::Deadline(due) => {
                result.kind = BridgeAgendaTimingKind::Deadline;
                result.due = Some(due.into());
            }
            core::AgendaTiming::AllDay { from, to } => {
                result.kind = BridgeAgendaTimingKind::AllDay;
                result.from = Some(from.to_string());
                result.to = Some(to.to_string());
            }
            core::AgendaTiming::Undated => {}
        }
        result
    }
}
impl From<core::SchoolAgendaStatus> for BridgeAgendaUpstreamStatus {
    fn from(v: core::SchoolAgendaStatus) -> Self {
        let mut result = Self {
            feature: BridgeAgendaFeature::Schedule,
            completed: v.completed(),
            begin_time: None,
            end_time: None,
            exam_status: None,
            checkin: None,
            pass: None,
            submission: None,
            text: None,
            order_status: None,
            check_status: None,
            sign_status: None,
            week_count: None,
            term_count: None,
        };
        match v {
            core::SchoolAgendaStatus::Schedule {
                begin_time,
                end_time,
            } => {
                result.begin_time = begin_time;
                result.end_time = end_time;
            }
            core::SchoolAgendaStatus::Exam { status } => {
                result.feature = BridgeAgendaFeature::Exam;
                result.exam_status = status;
            }
            core::SchoolAgendaStatus::Bykc { checkin, pass } => {
                result.feature = BridgeAgendaFeature::Bykc;
                result.checkin = checkin;
                result.pass = pass;
            }
            core::SchoolAgendaStatus::Spoc { status, text } => {
                result.feature = BridgeAgendaFeature::Spoc;
                result.text = Some(text);
                result.submission = Some(match status {
                    core::SpocSubmissionStatus::Submitted => BridgeAgendaSubmission::Submitted,
                    core::SpocSubmissionStatus::Unsubmitted => BridgeAgendaSubmission::Unsubmitted,
                    core::SpocSubmissionStatus::Unknown => BridgeAgendaSubmission::Unknown,
                });
            }
            core::SchoolAgendaStatus::Judge { status, text } => {
                result.feature = BridgeAgendaFeature::Judge;
                result.text = Some(text);
                result.submission = Some(match status {
                    core::JudgeSubmissionStatus::Submitted => BridgeAgendaSubmission::Submitted,
                    core::JudgeSubmissionStatus::Partial => BridgeAgendaSubmission::Partial,
                    core::JudgeSubmissionStatus::Unsubmitted => BridgeAgendaSubmission::Unsubmitted,
                    core::JudgeSubmissionStatus::Unknown => BridgeAgendaSubmission::Unknown,
                });
            }
            core::SchoolAgendaStatus::Cgyy {
                order_status,
                check_status,
            } => {
                result.feature = BridgeAgendaFeature::Cgyy;
                result.order_status = order_status;
                result.check_status = check_status;
            }
            core::SchoolAgendaStatus::Signin { sign_status } => {
                result.feature = BridgeAgendaFeature::Signin;
                result.sign_status = sign_status;
            }
            core::SchoolAgendaStatus::Ygdk {
                week_count,
                term_count,
            } => {
                result.feature = BridgeAgendaFeature::Ygdk;
                result.week_count = week_count;
                result.term_count = Some(term_count);
            }
        }
        result
    }
}
impl From<core::AgendaNavigation> for BridgeAgendaNavigation {
    fn from(v: core::AgendaNavigation) -> Self {
        let mut r = Self {
            feature: v.feature().into(),
            term: None,
            week: None,
            course_code: None,
            serial: None,
            day: None,
            section: None,
            course_id: None,
            bykc_course_id: None,
            assignment_id: None,
            order_id: None,
            task_id: None,
            course_no: None,
            course_name: None,
            date: None,
            start_time: None,
        };
        match v {
            core::AgendaNavigation::Schedule {
                term,
                week,
                course_code,
                serial,
                day,
                section,
            } => {
                r.term = Some(term);
                r.week = Some(week);
                r.course_code = Some(course_code);
                r.serial = serial;
                r.day = Some(day);
                r.section = Some(section);
            }
            core::AgendaNavigation::Exam {
                term,
                task_id,
                course_no,
                course_name,
                date,
                start_time,
            } => {
                r.term = Some(term);
                r.task_id = task_id;
                r.course_no = course_no;
                r.course_name = Some(course_name);
                r.date = Some(date.to_string());
                r.start_time = start_time;
            }
            core::AgendaNavigation::Bykc { course_id } => r.bykc_course_id = Some(course_id),
            core::AgendaNavigation::Spoc { assignment_id } => r.assignment_id = Some(assignment_id),
            core::AgendaNavigation::Judge {
                course_id,
                assignment_id,
            } => {
                r.course_id = Some(course_id);
                r.assignment_id = Some(assignment_id);
            }
            core::AgendaNavigation::Cgyy { order_id } => r.order_id = Some(order_id),
            core::AgendaNavigation::Signin { course_id, date } => {
                r.course_id = Some(course_id);
                r.date = Some(date.to_string());
            }
            core::AgendaNavigation::Ygdk => {}
        }
        r
    }
}
impl From<core::SchoolAgendaItem> for BridgeSchoolAgendaItem {
    fn from(v: core::SchoolAgendaItem) -> Self {
        Self {
            key: v.key.into(),
            timing: v.timing.into(),
            sort_time: v.sort_time.map(Into::into),
            title: v.title,
            subtitle: v.subtitle,
            location: v.location,
            status_label: v.status_label,
            upstream_status: v.upstream_status.into(),
            navigation: v.navigation.into(),
            home_todo: v.home_todo,
        }
    }
}
pub(super) fn result(
    v: core::AgendaQueryResult,
    now: core::AgendaTime,
    school_cache_failure: Option<crate::api::offline::BridgeCacheFailure>,
) -> BridgeAgendaQueryResult {
    BridgeAgendaQueryResult {
        entries: v.entries.into_iter().map(|e| entry(e, now)).collect(),
        sources: v.sources.into_iter().map(Into::into).collect(),
        school_cache_failure,
    }
}

pub(super) fn entry(e: core::AgendaEntry, now: core::AgendaTime) -> BridgeAgendaEntry {
    let timing = e.timing();
    let sort_time = e.sort_time().map(Into::into);
    let soon = timing.is_soon_at(now);
    let (local, school) = match e.item {
        core::AgendaEntryItem::Local(v) => (Some(v.into()), None),
        core::AgendaEntryItem::School(v) => (None, Some(v.into())),
    };
    BridgeAgendaEntry {
        local,
        school,
        timing: timing.into(),
        sort_time,
        soon,
        completed: e.completed,
        hidden: e.hidden,
        note: e.note,
    }
}
