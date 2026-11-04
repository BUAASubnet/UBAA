//! 从既有缓存刷新结果中取出命令所需的 typed 数据。
use ubaa_core::facade as core;

pub(in crate::api::command) fn portal_profile(
    v: core::CampusReadData,
) -> Option<core::PortalProfile> {
    if let core::CampusReadData::Profile(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn campus_metrics(
    v: core::CampusReadData,
) -> Option<core::CampusMetrics> {
    if let core::CampusReadData::Metrics(v) = v {
        Some(v.online)
    } else {
        None
    }
}

pub(in crate::api::command) fn network_usage(
    v: core::CampusReadData,
) -> Option<core::NetworkUsage> {
    if let core::CampusReadData::NetworkUsage(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn signin_today(
    v: core::HomeReadData,
) -> Option<Vec<core::SigninClass>> {
    if let core::HomeReadData::Signin(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn libbook_libraries(
    v: core::LibBookReadData,
) -> Option<Vec<core::LibBookLibrary>> {
    if let core::LibBookReadData::Libraries(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn libbook_areas(
    v: core::LibBookReadData,
) -> Option<Vec<core::LibBookArea>> {
    if let core::LibBookReadData::Areas(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn libbook_area_detail(
    v: core::LibBookReadData,
) -> Option<core::LibBookAreaDetail> {
    if let core::LibBookReadData::AreaDetail(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn libbook_seats(
    v: core::LibBookReadData,
) -> Option<Vec<core::LibBookSeat>> {
    if let core::LibBookReadData::Seats(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn libbook_bookings(
    v: core::LibBookReadData,
) -> Option<core::LibBookBookingsPage> {
    if let core::LibBookReadData::Bookings(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn cgyy_sites(
    v: core::CgyyReadData,
) -> Option<Vec<core::CgyyVenueSite>> {
    if let core::CgyyReadData::Sites(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn cgyy_purposes(
    v: core::CgyyReadData,
) -> Option<Vec<core::CgyyPurposeType>> {
    if let core::CgyyReadData::Purposes(v) = v {
        Some(v.items)
    } else {
        None
    }
}

pub(in crate::api::command) fn cgyy_day(v: core::CgyyReadData) -> Option<core::CgyyDayInfo> {
    if let core::CgyyReadData::Day(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn cgyy_orders(v: core::CgyyReadData) -> Option<core::CgyyOrdersPage> {
    if let core::CgyyReadData::Orders(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn cgyy_order_detail(v: core::CgyyReadData) -> Option<core::CgyyOrder> {
    if let core::CgyyReadData::Detail(v) = v {
        Some(*v)
    } else {
        None
    }
}

pub(in crate::api::command) fn bykc_profile(
    v: core::BykcReadData,
) -> Option<core::BykcUserProfile> {
    if let core::BykcReadData::Profile(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn bykc_courses(v: core::BykcReadData) -> Option<core::BykcCoursePage> {
    if let core::BykcReadData::Courses(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn bykc_course_detail(
    v: core::BykcReadData,
) -> Option<core::BykcCourse> {
    if let core::BykcReadData::Detail(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn bykc_chosen_courses(
    v: core::BykcReadData,
) -> Option<Vec<core::BykcChosenCourse>> {
    if let core::BykcReadData::Chosen { courses, .. } = v {
        Some(courses)
    } else {
        None
    }
}

pub(in crate::api::command) fn bykc_statistics(
    v: core::BykcReadData,
) -> Option<core::BykcStatistics> {
    if let core::BykcReadData::Statistics(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn ygdk_overview(v: core::HomeReadData) -> Option<core::YgdkOverview> {
    if let core::HomeReadData::YgdkOverview(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn schedule_terms(v: core::CachePayload) -> Option<Vec<core::Term>> {
    if let core::CachePayload::Terms(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn schedule_weeks(v: core::CachePayload) -> Option<Vec<core::Week>> {
    if let core::CachePayload::Weeks(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn schedule_week(
    v: core::CachePayload,
) -> Option<core::WeeklySchedule> {
    if let core::CachePayload::Week(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn exam_arrangement(
    v: core::CachePayload,
) -> Option<core::ExamArrangement> {
    if let core::CachePayload::Exams(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn grades(v: core::CachePayload) -> Option<core::GradeData> {
    if let core::CachePayload::Grades(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn classroom_search(
    v: core::CachePayload,
) -> Option<core::ClassroomQuery> {
    if let core::CachePayload::Classrooms(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn spoc_assignments(
    v: core::HomeReadData,
) -> Option<core::SpocAssignments> {
    if let core::HomeReadData::SpocAssignments(v) = v {
        Some(v)
    } else {
        None
    }
}

pub(in crate::api::command) fn spoc_assignment(
    v: core::HomeReadData,
) -> Option<core::SpocAssignmentDetail> {
    if let core::HomeReadData::SpocDetail(v) = v {
        Some(v)
    } else {
        None
    }
}
