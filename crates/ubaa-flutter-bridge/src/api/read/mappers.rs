//! Core 读取 DTO 到稳定 FRB 投影的显式字段映射。

use ubaa_core::facade as domain;

use super::{
    BridgeActionEligibility, BridgeBykcChosenCourse, BridgeBykcCourse, BridgeBykcCourseCategory,
    BridgeBykcCoursePage, BridgeBykcCourseStatus, BridgeBykcCourseSubCategory,
    BridgeBykcSignConfig, BridgeBykcSignPoint, BridgeBykcStatistic, BridgeBykcStatistics,
    BridgeBykcUserProfile, BridgeCgyyCancelOrderTarget, BridgeCgyyDayInfo, BridgeCgyyLockCode,
    BridgeCgyyOrder, BridgeCgyyOrdersPage, BridgeCgyyPurposeSource, BridgeCgyyPurposeType,
    BridgeCgyyPurposeTypes, BridgeCgyyReservationTarget, BridgeCgyySlotStatus,
    BridgeCgyySpaceAvailability, BridgeCgyyTimeSlot, BridgeCgyyVenueSite, BridgeClassroomFloor,
    BridgeClassroomInfo, BridgeClassroomQuery, BridgeCourseClass, BridgeEvaluationCourse,
    BridgeEvaluationCoursesResponse, BridgeEvaluationProgress, BridgeExam, BridgeExamArrangement,
    BridgeGrade, BridgeGradeData, BridgeJudgeAssignmentDetail, BridgeJudgeAssignmentSummary,
    BridgeJudgeProblem, BridgeJudgeSubmissionStatus, BridgeLibBookArea, BridgeLibBookAreaDetail,
    BridgeLibBookBooking, BridgeLibBookBookingsPage, BridgeLibBookLibrary, BridgeLibBookSeat,
    BridgeLibBookStorey, BridgeLibBookTimeSlot, BridgeSigninClass, BridgeSpocAssignmentDetail,
    BridgeSpocAssignmentSummary, BridgeSpocAssignments, BridgeSpocSubmissionStatus, BridgeTerm,
    BridgeTodayClass, BridgeWeek, BridgeWeeklySchedule, BridgeYgdkItem, BridgeYgdkOverview,
    BridgeYgdkRecord, BridgeYgdkRecordsPage, BridgeYgdkSubmitTarget, BridgeYgdkTermSummary,
};

// 转换函数保持显式字段清单；禁止使用 serde/json 反射把 Core DTO 整体透传。
pub(super) fn map_terms(values: Vec<domain::Term>) -> Vec<BridgeTerm> {
    values
        .into_iter()
        .map(|v| BridgeTerm {
            item_code: v.item_code,
            item_name: v.item_name,
            selected: v.selected,
            item_index: v.item_index,
        })
        .collect()
}
pub(super) fn map_weeks(values: Vec<domain::Week>) -> Vec<BridgeWeek> {
    values
        .into_iter()
        .map(|v| BridgeWeek {
            start_date: v.start_date,
            end_date: v.end_date,
            term: v.term,
            cur_week: v.cur_week,
            serial_number: v.serial_number,
            name: v.name,
        })
        .collect()
}
fn map_course(v: domain::CourseClass) -> BridgeCourseClass {
    BridgeCourseClass {
        course_code: v.course_code,
        course_name: v.course_name,
        course_serial_no: v.course_serial_no,
        credit: v.credit,
        begin_time: v.begin_time,
        end_time: v.end_time,
        begin_section: v.begin_section,
        end_section: v.end_section,
        place_name: v.place_name,
        weeks_and_teachers: v.weeks_and_teachers,
        teaching_target: v.teaching_target,
        color: v.color,
        day_of_week: v.day_of_week,
    }
}
pub(super) fn map_weekly_schedule(v: domain::WeeklySchedule) -> BridgeWeeklySchedule {
    BridgeWeeklySchedule {
        arranged_list: v.arranged_list.into_iter().map(map_course).collect(),
        code: v.code,
        name: v.name,
    }
}
pub(super) fn map_today_classes(values: Vec<domain::TodayClass>) -> Vec<BridgeTodayClass> {
    values
        .into_iter()
        .map(|v| BridgeTodayClass {
            biz_name: v.biz_name,
            place: v.place,
            time: v.time,
            short_name: v.short_name,
        })
        .collect()
}
fn map_exam(v: domain::Exam) -> BridgeExam {
    BridgeExam {
        course_name: v.course_name,
        course_no: v.course_no,
        exam_time_description: v.exam_time_description,
        exam_date: v.exam_date,
        start_time: v.start_time,
        end_time: v.end_time,
        exam_place: v.exam_place,
        exam_seat_no: v.exam_seat_no,
        week: v.week,
        exam_status: v.exam_status,
        exam_type: v.exam_type,
        task_id: v.task_id,
    }
}
pub(super) fn map_exam_arrangement(v: domain::ExamArrangement) -> BridgeExamArrangement {
    BridgeExamArrangement {
        arranged: v.arranged.into_iter().map(map_exam).collect(),
        not_arranged: v.not_arranged.into_iter().map(map_exam).collect(),
    }
}
fn map_grade(v: domain::Grade) -> BridgeGrade {
    BridgeGrade {
        course_name: v.course_name,
        course_code: v.course_code,
        credit: v.credit,
        score: v.score,
        grade_point: v.grade_point,
        course_type: v.course_type,
        score_type: v.score_type,
        term_code: v.term_code,
    }
}
pub(super) fn map_grade_data(v: domain::GradeData) -> BridgeGradeData {
    BridgeGradeData {
        term_code: v.term_code,
        grades: v.grades.into_iter().map(map_grade).collect(),
    }
}
pub(super) fn map_classroom_query(v: domain::ClassroomQuery) -> BridgeClassroomQuery {
    BridgeClassroomQuery {
        code: v.code,
        message: v.message,
        floors: v
            .floors
            .into_iter()
            .map(|(name, rooms)| BridgeClassroomFloor {
                name,
                rooms: rooms
                    .into_iter()
                    .map(|r| BridgeClassroomInfo {
                        id: r.id,
                        floor_id: r.floor_id,
                        name: r.name,
                        available_sections: r.available_sections,
                    })
                    .collect(),
            })
            .collect(),
    }
}
pub(super) fn map_signin_classes(values: Vec<domain::SigninClass>) -> Vec<BridgeSigninClass> {
    values
        .into_iter()
        .map(|v| BridgeSigninClass {
            course_id: v.course_id,
            course_name: v.course_name,
            class_begin_time: v.class_begin_time,
            class_end_time: v.class_end_time,
            sign_status: v.sign_status,
            signin_eligibility: map_action_eligibility(v.signin_eligibility),
            signin_target: v.signin_target,
        })
        .collect()
}
fn map_spoc_status(v: domain::SpocSubmissionStatus) -> BridgeSpocSubmissionStatus {
    match v {
        domain::SpocSubmissionStatus::Submitted => BridgeSpocSubmissionStatus::Submitted,
        domain::SpocSubmissionStatus::Unsubmitted => BridgeSpocSubmissionStatus::Unsubmitted,
        domain::SpocSubmissionStatus::Unknown => BridgeSpocSubmissionStatus::Unknown,
    }
}
fn map_spoc_summary(v: domain::SpocAssignmentSummary) -> BridgeSpocAssignmentSummary {
    BridgeSpocAssignmentSummary {
        assignment_id: v.assignment_id,
        course_id: v.course_id,
        course_name: v.course_name,
        teacher_name: v.teacher_name,
        title: v.title,
        start_time: v.start_time,
        due_time: v.due_time,
        score: v.score,
        submission_status: map_spoc_status(v.submission_status),
        submission_status_text: v.submission_status_text,
    }
}
pub(super) fn map_spoc_assignments(v: domain::SpocAssignments) -> BridgeSpocAssignments {
    BridgeSpocAssignments {
        term_code: v.term_code,
        term_name: v.term_name,
        assignments: v.assignments.into_iter().map(map_spoc_summary).collect(),
    }
}
pub(super) fn map_spoc_detail(v: domain::SpocAssignmentDetail) -> BridgeSpocAssignmentDetail {
    BridgeSpocAssignmentDetail {
        assignment_id: v.assignment_id,
        course_id: v.course_id,
        course_name: v.course_name,
        teacher_name: v.teacher_name,
        title: v.title,
        start_time: v.start_time,
        due_time: v.due_time,
        score: v.score,
        submission_status: map_spoc_status(v.submission_status),
        submission_status_text: v.submission_status_text,
        content_plain_text: v.content_plain_text,
        submitted_at: v.submitted_at,
    }
}
fn map_judge_status(v: domain::JudgeSubmissionStatus) -> BridgeJudgeSubmissionStatus {
    match v {
        domain::JudgeSubmissionStatus::Submitted => BridgeJudgeSubmissionStatus::Submitted,
        domain::JudgeSubmissionStatus::Partial => BridgeJudgeSubmissionStatus::Partial,
        domain::JudgeSubmissionStatus::Unsubmitted => BridgeJudgeSubmissionStatus::Unsubmitted,
        domain::JudgeSubmissionStatus::Unknown => BridgeJudgeSubmissionStatus::Unknown,
    }
}
fn map_judge_summary(v: domain::JudgeAssignmentSummary) -> BridgeJudgeAssignmentSummary {
    BridgeJudgeAssignmentSummary {
        course_id: v.course_id,
        course_name: v.course_name,
        assignment_id: v.assignment_id,
        title: v.title,
        start_time: v.start_time,
        due_time: v.due_time,
        max_score: v.max_score,
        my_score: v.my_score,
        total_problems: v.total_problems,
        submitted_count: v.submitted_count,
        submission_status: map_judge_status(v.submission_status),
        submission_status_text: v.submission_status_text,
    }
}
fn map_judge_problem(v: domain::JudgeProblem) -> BridgeJudgeProblem {
    BridgeJudgeProblem {
        name: v.name,
        score: v.score,
        max_score: v.max_score,
        status: map_judge_status(v.status),
        status_text: v.status_text,
    }
}
pub(super) fn map_judge_detail(v: domain::JudgeAssignmentDetail) -> BridgeJudgeAssignmentDetail {
    BridgeJudgeAssignmentDetail {
        course_id: v.course_id,
        course_name: v.course_name,
        assignment_id: v.assignment_id,
        title: v.title,
        start_time: v.start_time,
        due_time: v.due_time,
        max_score: v.max_score,
        my_score: v.my_score,
        total_problems: v.total_problems,
        submitted_count: v.submitted_count,
        submission_status: map_judge_status(v.submission_status),
        submission_status_text: v.submission_status_text,
        problems: v.problems.into_iter().map(map_judge_problem).collect(),
        content_plain_text: v.content_plain_text,
    }
}
pub(super) fn map_judge_summaries(
    v: Vec<domain::JudgeAssignmentSummary>,
) -> Vec<BridgeJudgeAssignmentSummary> {
    v.into_iter().map(map_judge_summary).collect()
}
pub(super) fn map_judge_details(
    v: Vec<domain::JudgeAssignmentDetail>,
) -> Vec<BridgeJudgeAssignmentDetail> {
    v.into_iter().map(map_judge_detail).collect()
}
fn map_bykc_status(v: domain::BykcCourseStatus) -> BridgeBykcCourseStatus {
    match v {
        domain::BykcCourseStatus::Expired => BridgeBykcCourseStatus::Expired,
        domain::BykcCourseStatus::Selected => BridgeBykcCourseStatus::Selected,
        domain::BykcCourseStatus::Preview => BridgeBykcCourseStatus::Preview,
        domain::BykcCourseStatus::Ended => BridgeBykcCourseStatus::Ended,
        domain::BykcCourseStatus::Full => BridgeBykcCourseStatus::Full,
        domain::BykcCourseStatus::Available => BridgeBykcCourseStatus::Available,
    }
}
fn map_action_eligibility(v: domain::ActionEligibility) -> BridgeActionEligibility {
    match v {
        domain::ActionEligibility::Allowed => BridgeActionEligibility::Allowed,
        domain::ActionEligibility::Denied => BridgeActionEligibility::Denied,
        domain::ActionEligibility::Unknown => BridgeActionEligibility::Unknown,
    }
}
pub(super) fn map_bykc_course(v: domain::BykcCourse) -> BridgeBykcCourse {
    BridgeBykcCourse {
        id: v.id,
        course_name: v.course_name,
        course_position: v.course_position,
        course_teacher: v.course_teacher,
        course_start_date: v.course_start_date,
        course_end_date: v.course_end_date,
        course_select_start_date: v.course_select_start_date,
        course_select_end_date: v.course_select_end_date,
        course_cancel_end_date: v.course_cancel_end_date,
        course_max_count: v.course_max_count,
        course_current_count: v.course_current_count,
        status: map_bykc_status(v.status),
        selected: v.selected,
        select_eligibility: map_action_eligibility(v.select_eligibility),
        deselect_eligibility: map_action_eligibility(v.deselect_eligibility),
    }
}
pub(super) fn map_bykc_profile(v: domain::BykcUserProfile) -> BridgeBykcUserProfile {
    BridgeBykcUserProfile {
        id: v.id,
        employee_id: v.employee_id,
        real_name: v.real_name,
        student_no: v.student_no,
        college_name: v.college_name,
    }
}
pub(super) fn map_bykc_course_page(v: domain::BykcCoursePage) -> BridgeBykcCoursePage {
    BridgeBykcCoursePage {
        content: v.content.into_iter().map(map_bykc_course).collect(),
        total_elements: v.total_elements,
        total_pages: v.total_pages,
        size: v.size,
        number: v.number,
    }
}
fn map_bykc_category(v: domain::BykcCourseCategory) -> BridgeBykcCourseCategory {
    match v {
        domain::BykcCourseCategory::Boya => BridgeBykcCourseCategory::Boya,
        domain::BykcCourseCategory::Unknown => BridgeBykcCourseCategory::Unknown,
    }
}
fn map_bykc_subcategory(v: domain::BykcCourseSubCategory) -> BridgeBykcCourseSubCategory {
    match v {
        domain::BykcCourseSubCategory::Moral => BridgeBykcCourseSubCategory::Moral,
        domain::BykcCourseSubCategory::Aesthetic => BridgeBykcCourseSubCategory::Aesthetic,
        domain::BykcCourseSubCategory::Labor => BridgeBykcCourseSubCategory::Labor,
        domain::BykcCourseSubCategory::SafetyHealth => BridgeBykcCourseSubCategory::SafetyHealth,
        domain::BykcCourseSubCategory::Other => BridgeBykcCourseSubCategory::Other,
        domain::BykcCourseSubCategory::Unknown => BridgeBykcCourseSubCategory::Unknown,
    }
}
fn map_bykc_sign_config(v: domain::BykcSignConfig) -> BridgeBykcSignConfig {
    BridgeBykcSignConfig {
        sign_start_date: v.sign_start_date,
        sign_end_date: v.sign_end_date,
        sign_out_start_date: v.sign_out_start_date,
        sign_out_end_date: v.sign_out_end_date,
        sign_points: v
            .sign_points
            .into_iter()
            .map(|p| BridgeBykcSignPoint {
                lat: p.lat,
                lng: p.lng,
                radius: p.radius,
            })
            .collect(),
    }
}
fn map_bykc_chosen(v: domain::BykcChosenCourse) -> BridgeBykcChosenCourse {
    BridgeBykcChosenCourse {
        id: v.id,
        course_id: v.course_id,
        course_name: v.course_name,
        course_position: v.course_position,
        course_teacher: v.course_teacher,
        course_start_date: v.course_start_date,
        course_end_date: v.course_end_date,
        select_date: v.select_date,
        course_cancel_end_date: v.course_cancel_end_date,
        category: v.category.map(map_bykc_category),
        sub_category: v.sub_category.map(map_bykc_subcategory),
        checkin: v.checkin,
        score: v.score,
        pass: v.pass,
        sign_eligibility: map_action_eligibility(v.sign_eligibility),
        sign_out_eligibility: map_action_eligibility(v.sign_out_eligibility),
        deselect_eligibility: map_action_eligibility(v.deselect_eligibility),
        sign_config: v.sign_config.map(map_bykc_sign_config),
        course_sign_type: v.course_sign_type,
    }
}
pub(super) fn map_bykc_chosen_courses(
    v: Vec<domain::BykcChosenCourse>,
) -> Vec<BridgeBykcChosenCourse> {
    v.into_iter().map(map_bykc_chosen).collect()
}
pub(super) fn map_bykc_statistics(v: domain::BykcStatistics) -> BridgeBykcStatistics {
    BridgeBykcStatistics {
        total_valid_count: v.total_valid_count,
        categories: v
            .categories
            .into_iter()
            .map(|s| BridgeBykcStatistic {
                category_name: s.category_name,
                sub_category_name: s.sub_category_name,
                required_count: s.required_count,
                passed_count: s.passed_count,
                qualified: s.qualified,
            })
            .collect(),
    }
}
fn map_libbook_storey(v: domain::LibBookStorey) -> BridgeLibBookStorey {
    BridgeLibBookStorey {
        id: v.id,
        name: v.name,
        free_num: v.free_num,
        total_num: v.total_num,
    }
}
pub(super) fn map_libbook_libraries(v: Vec<domain::LibBookLibrary>) -> Vec<BridgeLibBookLibrary> {
    v.into_iter()
        .map(|l| BridgeLibBookLibrary {
            id: l.id,
            name: l.name,
            free_num: l.free_num,
            total_num: l.total_num,
            storeys: l.storeys.into_iter().map(map_libbook_storey).collect(),
        })
        .collect()
}
pub(super) fn map_libbook_areas(v: Vec<domain::LibBookArea>) -> Vec<BridgeLibBookArea> {
    v.into_iter()
        .map(|a| BridgeLibBookArea {
            id: a.id,
            name: a.name,
            area_name: a.area_name,
            premises_id: a.premises_id,
            storey_id: a.storey_id,
            free_num: a.free_num,
            total_num: a.total_num,
        })
        .collect()
}
pub(super) fn map_libbook_area_detail(v: domain::LibBookAreaDetail) -> BridgeLibBookAreaDetail {
    BridgeLibBookAreaDetail {
        id: v.id,
        name: v.name,
        available_dates: v.available_dates,
        time_slots: v
            .time_slots
            .into_iter()
            .map(|s| BridgeLibBookTimeSlot {
                id: s.id,
                start: s.start,
                end: s.end,
                label: s.label,
            })
            .collect(),
    }
}
pub(super) fn map_libbook_seats(v: Vec<domain::LibBookSeat>) -> Vec<BridgeLibBookSeat> {
    v.into_iter()
        .map(|s| BridgeLibBookSeat {
            id: s.id,
            name: s.name,
            no: s.no,
            status: s.status,
            status_name: s.status_name,
            reserve_eligibility: map_action_eligibility(s.reserve_eligibility),
            reserve_target: s.reserve_target,
        })
        .collect()
}
fn map_libbook_booking(v: domain::LibBookBooking) -> BridgeLibBookBooking {
    BridgeLibBookBooking {
        id: v.id,
        name_merge: v.name_merge,
        area_name: v.area_name,
        seat_no: v.seat_no,
        day: v.day,
        begin_time: v.begin_time,
        end_time: v.end_time,
        status: v.status,
        status_name: v.status_name,
        cancel_eligibility: map_action_eligibility(v.cancel_eligibility),
        cancel_target: v.cancel_target,
    }
}
pub(super) fn map_libbook_bookings(v: domain::LibBookBookingsPage) -> BridgeLibBookBookingsPage {
    BridgeLibBookBookingsPage {
        bookings: v.bookings.into_iter().map(map_libbook_booking).collect(),
        page: v.page,
        limit: v.limit,
        total: v.total,
    }
}
fn map_ygdk_summary(v: domain::YgdkTermSummary) -> BridgeYgdkTermSummary {
    BridgeYgdkTermSummary {
        term_id: v.term_id,
        term_name: v.term_name,
        term_count: v.term_count,
        term_target: v.term_target,
        week_count: v.week_count,
        week_target: v.week_target,
        month_count: v.month_count,
        month_target: v.month_target,
        day_count: v.day_count,
        good_count: v.good_count,
    }
}
pub(super) fn map_ygdk_overview(v: domain::YgdkOverview) -> BridgeYgdkOverview {
    let classify_id = v.classify_id;
    let classify_is_canonical = classify_id > 0 && !v.classify_name.trim().is_empty();
    let mut item_id_counts = std::collections::BTreeMap::<i32, usize>::new();
    for item in &v.items {
        *item_id_counts.entry(item.item_id).or_default() += 1;
    }
    BridgeYgdkOverview {
        summary: map_ygdk_summary(v.summary),
        classify_id,
        classify_name: v.classify_name,
        default_item_id: v.default_item_id,
        default_item_name: v.default_item_name,
        items: v
            .items
            .into_iter()
            .map(|i| {
                let target_is_canonical = i.submit_target.is_some_and(|target| {
                    target.classify_id == classify_id
                        && target.item_id == i.item_id
                        && target.classify_id > 0
                        && target.item_id > 0
                });
                let item_is_unique = item_id_counts.get(&i.item_id) == Some(&1);
                let item_is_canonical =
                    classify_is_canonical && i.item_id > 0 && !i.name.trim().is_empty();
                let allowed = i.submit_eligibility == domain::ActionEligibility::Allowed
                    && item_is_canonical
                    && item_is_unique
                    && target_is_canonical;
                let denied = i.submit_eligibility == domain::ActionEligibility::Denied
                    && item_is_canonical
                    && item_is_unique
                    && i.submit_target.is_none();
                BridgeYgdkItem {
                    item_id: i.item_id,
                    name: i.name,
                    kind: i.kind,
                    sort: i.sort,
                    submit_eligibility: if allowed {
                        BridgeActionEligibility::Allowed
                    } else if denied {
                        BridgeActionEligibility::Denied
                    } else {
                        BridgeActionEligibility::Unknown
                    },
                    submit_target: allowed.then(|| {
                        let target = i.submit_target.expect("allowed target was checked");
                        BridgeYgdkSubmitTarget {
                            classify_id: target.classify_id,
                            item_id: target.item_id,
                        }
                    }),
                }
            })
            .collect(),
    }
}
pub(super) fn map_ygdk_records(v: domain::YgdkRecordsPage) -> BridgeYgdkRecordsPage {
    BridgeYgdkRecordsPage {
        content: v
            .content
            .into_iter()
            .map(|r| BridgeYgdkRecord {
                record_id: r.record_id,
                item_id: r.item_id,
                item_name: r.item_name,
                start_time: r.start_time,
                end_time: r.end_time,
                place: r.place,
                image_count: i32::try_from(r.images.len()).unwrap_or(i32::MAX),
                is_open: r.is_open,
                state: r.state,
                created_at: r.created_at,
                created_at_label: r.created_at_label,
            })
            .collect(),
        total: v.total,
        page: v.page,
        size: v.size,
        has_more: v.has_more,
    }
}
pub(super) fn map_cgyy_sites(v: Vec<domain::CgyyVenueSite>) -> Vec<BridgeCgyyVenueSite> {
    v.into_iter()
        .map(|s| BridgeCgyyVenueSite {
            id: s.id,
            site_name: s.site_name,
            venue_name: s.venue_name,
            campus_name: s.campus_name,
            seat_count: s.seat_count,
            reservation_space_count: s.reservation_space_count,
            site_telephone: s.site_telephone,
            open_start_date: s.open_start_date,
            open_end_date: s.open_end_date,
        })
        .collect()
}
pub(super) fn map_cgyy_purpose_types(v: domain::CgyyPurposeTypes) -> BridgeCgyyPurposeTypes {
    BridgeCgyyPurposeTypes {
        items: v
            .items
            .into_iter()
            .map(|p| BridgeCgyyPurposeType {
                key: p.key,
                name: p.name,
            })
            .collect(),
        source: match v.source {
            domain::CgyyPurposeSource::Upstream => BridgeCgyyPurposeSource::Upstream,
            domain::CgyyPurposeSource::StaticFallback => BridgeCgyyPurposeSource::StaticFallback,
        },
    }
}
fn map_cgyy_time_slot(v: domain::CgyyTimeSlot) -> BridgeCgyyTimeSlot {
    BridgeCgyyTimeSlot {
        id: v.id,
        begin_time: v.begin_time,
        end_time: v.end_time,
        label: v.label,
    }
}
fn map_cgyy_slot(v: domain::CgyySlotStatus) -> BridgeCgyySlotStatus {
    BridgeCgyySlotStatus {
        time_id: v.time_id,
        reservation_status: v.reservation_status,
        reservation_eligibility: map_action_eligibility(v.reservation_eligibility),
        reservation_target: v
            .reservation_target
            .map(|target| BridgeCgyyReservationTarget {
                venue_site_id: target.venue_site_id,
                reservation_date: target.reservation_date,
                space_id: target.space_id,
                time_id: target.time_id,
                venue_space_group_id: target.venue_space_group_id,
                time_ordinal: target.time_ordinal,
            }),
        start_date: v.start_date,
        end_date: v.end_date,
    }
}
pub(super) fn map_cgyy_day_info(v: domain::CgyyDayInfo) -> BridgeCgyyDayInfo {
    BridgeCgyyDayInfo {
        venue_site_id: v.venue_site_id,
        reservation_date: v.reservation_date,
        available_dates: v.available_dates,
        time_slots: v.time_slots.into_iter().map(map_cgyy_time_slot).collect(),
        spaces: v
            .spaces
            .into_iter()
            .map(|s| BridgeCgyySpaceAvailability {
                space_id: s.space_id,
                space_name: s.space_name,
                venue_site_id: s.venue_site_id,
                venue_space_group_id: s.venue_space_group_id,
                slots: s.slots.into_iter().map(map_cgyy_slot).collect(),
            })
            .collect(),
        reservation_total_num: v.reservation_total_num,
    }
}
pub(crate) fn map_cgyy_order(v: domain::CgyyOrder) -> BridgeCgyyOrder {
    let core_cancel_target_is_none = v.cancel_target.is_none();
    let (cancel_eligibility, cancel_target) = match (v.cancel_eligibility, v.cancel_target) {
        (domain::ActionEligibility::Allowed, Some(target))
            if v.id > 0 && target.order_id == v.id =>
        {
            (
                BridgeActionEligibility::Allowed,
                Some(BridgeCgyyCancelOrderTarget {
                    order_id: target.order_id,
                }),
            )
        }
        (domain::ActionEligibility::Denied, _) => (BridgeActionEligibility::Denied, None),
        _ => (BridgeActionEligibility::Unknown, None),
    };
    let cancelled_target = v
        .cancelled_target
        .filter(|target| {
            target.order_id > 0
                && target.order_id == v.id
                && matches!(cancel_eligibility, BridgeActionEligibility::Denied)
                && v.order_status == Some(2)
                && core_cancel_target_is_none
                && cancel_target.is_none()
        })
        .map(|target| BridgeCgyyCancelOrderTarget {
            order_id: target.order_id,
        });
    BridgeCgyyOrder {
        id: v.id,
        venue_site_id: v.venue_site_id,
        reservation_date: v.reservation_date,
        reservation_date_detail: v.reservation_date_detail,
        venue_space_name: v.venue_space_name,
        campus_name: v.campus_name,
        venue_name: v.venue_name,
        site_name: v.site_name,
        reservation_start_date: v.reservation_start_date,
        reservation_end_date: v.reservation_end_date,
        order_status: v.order_status,
        check_status: v.check_status,
        theme: v.theme,
        purpose_type_name: v.purpose_type_name,
        joiner_num: v.joiner_num,
        cancel_eligibility,
        cancel_target,
        cancelled_target,
    }
}
pub(super) fn map_cgyy_orders(v: domain::CgyyOrdersPage) -> BridgeCgyyOrdersPage {
    BridgeCgyyOrdersPage {
        content: v.content.into_iter().map(map_cgyy_order).collect(),
        total_elements: v.total_elements,
        total_pages: v.total_pages,
        size: v.size,
        number: v.number,
    }
}
pub(super) fn map_cgyy_lock_code(v: domain::CgyyLockCode) -> BridgeCgyyLockCode {
    BridgeCgyyLockCode {
        available: v.available,
    }
}
pub(super) fn map_evaluation(
    v: domain::EvaluationCoursesResponse,
) -> BridgeEvaluationCoursesResponse {
    BridgeEvaluationCoursesResponse {
        courses: v
            .courses
            .into_iter()
            .map(|c| BridgeEvaluationCourse {
                id: c.id,
                kcmc: c.kcmc,
                bpmc: c.bpmc,
                is_evaluated: c.is_evaluated,
                rwid: c.rwid,
                wjid: c.wjid,
                kcdm: c.kcdm,
                bpdm: c.bpdm,
                pjrdm: c.pjrdm,
                pjrmc: c.pjrmc,
                xnxq: c.xnxq,
                msid: c.msid,
                zdmc: c.zdmc,
                ypjcs: c.ypjcs,
                xypjcs: c.xypjcs,
                sxz: c.sxz,
                rwh: c.rwh,
                xn: c.xn,
                xq: c.xq,
                pjlxid: c.pjlxid,
                sfksqbpj: c.sfksqbpj,
                yxsfktjst: c.yxsfktjst,
            })
            .collect(),
        progress: BridgeEvaluationProgress {
            total_courses: v.progress.total_courses,
            evaluated_courses: v.progress.evaluated_courses,
            pending_courses: v.progress.pending_courses,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 场馆订单读取只投影typed取消资格与canonical目标() {
        let allowed = map_cgyy_order(domain::CgyyOrder {
            id: 42,
            cancel_eligibility: domain::ActionEligibility::Allowed,
            cancel_target: Some(domain::CgyyCancelOrderTarget { order_id: 42 }),
            ..domain::CgyyOrder::default()
        });
        assert!(matches!(
            allowed.cancel_eligibility,
            BridgeActionEligibility::Allowed
        ));
        assert_eq!(
            allowed.cancel_target.expect("Allowed 必须有目标").order_id,
            42
        );
        assert!(allowed.cancelled_target.is_none());

        for eligibility in [
            domain::ActionEligibility::Denied,
            domain::ActionEligibility::Unknown,
        ] {
            let projected = map_cgyy_order(domain::CgyyOrder {
                id: 42,
                cancel_eligibility: eligibility,
                cancel_target: None,
                ..domain::CgyyOrder::default()
            });
            assert!(projected.cancel_target.is_none());
        }

        for (id, target_id) in [(42, 41), (0, 0), (-1, -1)] {
            let projected = map_cgyy_order(domain::CgyyOrder {
                id,
                cancel_eligibility: domain::ActionEligibility::Allowed,
                cancel_target: Some(domain::CgyyCancelOrderTarget {
                    order_id: target_id,
                }),
                ..domain::CgyyOrder::default()
            });
            assert!(matches!(
                projected.cancel_eligibility,
                BridgeActionEligibility::Unknown
            ));
            assert!(projected.cancel_target.is_none());
        }
    }

    #[test]
    fn 阳光打卡读取只投影同父级唯一正数typed目标() {
        let item = |item_id, eligibility, target| domain::YgdkItem {
            item_id,
            name: "脱敏项目".to_owned(),
            submit_eligibility: eligibility,
            submit_target: target,
            ..domain::YgdkItem::default()
        };
        let target = |classify_id, item_id| {
            Some(domain::YgdkSubmitTarget {
                classify_id,
                item_id,
            })
        };
        let overview = map_ygdk_overview(domain::YgdkOverview {
            classify_id: 3,
            classify_name: "阳光体育".to_owned(),
            items: vec![
                item(2, domain::ActionEligibility::Allowed, target(3, 2)),
                item(4, domain::ActionEligibility::Allowed, target(3, 4)),
                item(4, domain::ActionEligibility::Allowed, target(3, 4)),
                item(5, domain::ActionEligibility::Allowed, target(9, 5)),
                item(6, domain::ActionEligibility::Allowed, None),
                item(7, domain::ActionEligibility::Denied, None),
                item(8, domain::ActionEligibility::Unknown, target(3, 8)),
                item(0, domain::ActionEligibility::Denied, None),
                item(9, domain::ActionEligibility::Denied, None),
                item(9, domain::ActionEligibility::Denied, None),
                domain::YgdkItem {
                    item_id: 10,
                    name: " \t".to_owned(),
                    submit_eligibility: domain::ActionEligibility::Denied,
                    submit_target: None,
                    ..domain::YgdkItem::default()
                },
            ],
            ..domain::YgdkOverview::default()
        });

        assert!(matches!(
            overview.items[0].submit_eligibility,
            BridgeActionEligibility::Allowed
        ));
        assert_eq!(
            overview.items[0]
                .submit_target
                .as_ref()
                .expect("canonical target")
                .item_id,
            2
        );
        for index in [1, 2, 3, 4, 6, 7, 8, 9, 10] {
            let item = &overview.items[index];
            assert!(matches!(
                item.submit_eligibility,
                BridgeActionEligibility::Unknown
            ));
            assert!(item.submit_target.is_none());
        }
        assert!(matches!(
            overview.items[5].submit_eligibility,
            BridgeActionEligibility::Denied
        ));
        assert!(overview.items[5].submit_target.is_none());
    }

    #[test]
    fn 场馆订单读取只投影一致的strict已取消证明() {
        let cancelled = map_cgyy_order(domain::CgyyOrder {
            id: 42,
            order_status: Some(2),
            cancel_eligibility: domain::ActionEligibility::Denied,
            cancel_target: None,
            cancelled_target: Some(domain::CgyyCancelOrderTarget { order_id: 42 }),
            ..domain::CgyyOrder::default()
        });
        assert!(cancelled.cancel_target.is_none());
        assert_eq!(
            cancelled
                .cancelled_target
                .expect("Core strict 已取消证明必须透传")
                .order_id,
            42
        );

        let compatible_but_unproven = map_cgyy_order(domain::CgyyOrder {
            id: 42,
            order_status: Some(2),
            cancel_eligibility: domain::ActionEligibility::Unknown,
            cancel_target: None,
            cancelled_target: None,
            ..domain::CgyyOrder::default()
        });
        assert!(compatible_but_unproven.cancelled_target.is_none());

        for (id, proof_id) in [(42, 41), (42, 0), (42, -1), (0, 0), (-1, -1)] {
            let invalid_proof = map_cgyy_order(domain::CgyyOrder {
                id,
                order_status: Some(2),
                cancel_eligibility: domain::ActionEligibility::Denied,
                cancel_target: None,
                cancelled_target: Some(domain::CgyyCancelOrderTarget { order_id: proof_id }),
                ..domain::CgyyOrder::default()
            });
            assert!(
                invalid_proof.cancelled_target.is_none(),
                "Bridge 不得投影非正数或与兼容 id 不一致的 Core proof：id={id}, proof={proof_id}",
            );
        }

        for (eligibility, order_status, has_cancel_target) in [
            (domain::ActionEligibility::Allowed, Some(2), true),
            (domain::ActionEligibility::Unknown, Some(2), false),
            (domain::ActionEligibility::Denied, Some(1), false),
            (domain::ActionEligibility::Denied, Some(2), true),
        ] {
            let contradictory = map_cgyy_order(domain::CgyyOrder {
                id: 42,
                order_status,
                cancel_eligibility: eligibility,
                cancel_target: has_cancel_target
                    .then_some(domain::CgyyCancelOrderTarget { order_id: 42 }),
                cancelled_target: Some(domain::CgyyCancelOrderTarget { order_id: 42 }),
                ..domain::CgyyOrder::default()
            });
            assert!(
                contradictory.cancelled_target.is_none(),
                "Bridge 不得投影与取消资格、状态或待取消目标矛盾的 proof",
            );
        }
    }
}
