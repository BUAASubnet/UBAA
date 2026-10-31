//! 首页读字段的逐来源转换，不处理网络或资格。
use super::home::{
    BridgeHomeBykc, BridgeHomeCgyy, BridgeHomeExam, BridgeHomeJudge, BridgeHomeSignin,
    BridgeHomeSpoc, BridgeHomeYgdk,
};
use super::{models::BridgeAgendaError, school::BridgeAgendaSubmission};
use ubaa_core::facade as core;
impl From<BridgeHomeBykc> for core::HomeAgendaRead {
    fn from(v: BridgeHomeBykc) -> Self {
        let BridgeHomeBykc {
            course_id,
            title,
            teacher,
            place,
            start,
            end,
            checkin,
            pass,
        } = v;
        core::HomeAgendaRead::Bykc(vec![core::CachedBykcChosenCourse {
            course_id,
            course_name: title,
            course_teacher: teacher,
            course_position: place,
            course_start_date: start,
            course_end_date: end,
            checkin,
            pass,
            ..Default::default()
        }])
    }
}
impl From<BridgeHomeSpoc> for core::HomeAgendaRead {
    fn from(v: BridgeHomeSpoc) -> Self {
        let BridgeHomeSpoc {
            assignment_id,
            title,
            course_name,
            teacher,
            start,
            due,
            status,
            status_text,
        } = v;
        core::HomeAgendaRead::Spoc(vec![core::SpocAssignmentSummary {
            assignment_id,
            title,
            course_name,
            teacher_name: teacher,
            start_time: start,
            due_time: due,
            submission_status: match status {
                BridgeAgendaSubmission::Submitted => core::SpocSubmissionStatus::Submitted,
                BridgeAgendaSubmission::Unsubmitted => core::SpocSubmissionStatus::Unsubmitted,
                _ => core::SpocSubmissionStatus::Unknown,
            },
            submission_status_text: status_text,
            ..Default::default()
        }])
    }
}
impl From<BridgeHomeJudge> for core::HomeAgendaRead {
    fn from(v: BridgeHomeJudge) -> Self {
        let BridgeHomeJudge {
            course_id,
            assignment_id,
            title,
            course_name,
            due,
            status,
            status_text,
        } = v;
        core::HomeAgendaRead::Judge(vec![core::JudgeAssignmentSummary {
            course_id,
            assignment_id,
            title,
            course_name,
            due_time: due,
            submission_status: match status {
                BridgeAgendaSubmission::Submitted => core::JudgeSubmissionStatus::Submitted,
                BridgeAgendaSubmission::Partial => core::JudgeSubmissionStatus::Partial,
                BridgeAgendaSubmission::Unsubmitted => core::JudgeSubmissionStatus::Unsubmitted,
                BridgeAgendaSubmission::Unknown => core::JudgeSubmissionStatus::Unknown,
            },
            submission_status_text: status_text,
            ..Default::default()
        }])
    }
}
impl From<BridgeHomeCgyy> for core::HomeAgendaRead {
    fn from(v: BridgeHomeCgyy) -> Self {
        let BridgeHomeCgyy {
            order_id,
            venue,
            space,
            site,
            theme,
            purpose,
            start,
            end,
            order_status,
            check_status,
        } = v;
        core::HomeAgendaRead::Cgyy(vec![core::CachedCgyyOrder {
            id: order_id,
            venue_name: venue,
            venue_space_name: space,
            site_name: site,
            theme,
            purpose_type_name: purpose,
            reservation_start_date: start,
            reservation_end_date: end,
            order_status,
            check_status,
            ..Default::default()
        }])
    }
}
impl TryFrom<BridgeHomeSignin> for core::HomeAgendaRead {
    type Error = BridgeAgendaError;
    fn try_from(v: BridgeHomeSignin) -> Result<Self, Self::Error> {
        let BridgeHomeSignin {
            fresh,
            date,
            course_id,
            title,
            start,
            end,
            sign_status,
        } = v;
        Ok(core::HomeAgendaRead::Signin {
            fresh,
            date: super::convert::date(&date)?,
            classes: vec![core::CachedSigninClass {
                course_id,
                course_name: title,
                class_begin_time: start,
                class_end_time: end,
                sign_status,
            }],
        })
    }
}
impl From<BridgeHomeExam> for core::HomeAgendaRead {
    fn from(v: BridgeHomeExam) -> Self {
        let BridgeHomeExam {
            term,
            title,
            task_id,
            course_no,
            date,
            start,
            end,
            place,
            seat,
            status,
        } = v;
        core::HomeAgendaRead::Exam {
            term,
            exams: vec![core::Exam {
                course_name: title,
                task_id,
                course_no,
                exam_date: date,
                start_time: start,
                end_time: end,
                exam_place: place,
                exam_seat_no: seat,
                exam_status: status,
                ..Default::default()
            }],
        }
    }
}
impl From<BridgeHomeYgdk> for core::HomeAgendaRead {
    fn from(v: BridgeHomeYgdk) -> Self {
        let BridgeHomeYgdk {
            week_count,
            term_count,
        } = v;
        core::HomeAgendaRead::Ygdk(core::CachedYgdkOverview {
            summary: core::YgdkTermSummary {
                week_count,
                term_count,
                ..Default::default()
            },
            classify_id: 0,
            classify_name: String::new(),
            default_item_id: 0,
            default_item_name: String::new(),
            items: Vec::new(),
        })
    }
}
