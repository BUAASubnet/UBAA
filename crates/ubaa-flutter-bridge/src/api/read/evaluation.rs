//! 教学评教安全公开投影与跨课程一致性校验。

use std::collections::HashMap;

use ubaa_core::facade as domain;

use super::{
    BridgeActionEligibility, BridgeEvaluationCourse, BridgeEvaluationCoursesResponse,
    BridgeEvaluationProgress, BridgeEvaluationSubmitTarget,
};

pub(super) fn map_evaluation(
    response: domain::EvaluationCoursesResponse,
) -> BridgeEvaluationCoursesResponse {
    let mut target_counts = HashMap::new();
    for target in response
        .courses
        .iter()
        .filter_map(|course| course.submit_target.clone())
        .filter_map(normalize_evaluation_target_identity)
    {
        *target_counts.entry(target).or_insert(0_usize) += 1;
    }
    BridgeEvaluationCoursesResponse {
        courses: response
            .courses
            .into_iter()
            .map(|course| map_evaluation_course(course, &target_counts))
            .collect(),
        progress: BridgeEvaluationProgress {
            total_courses: response.progress.total_courses,
            evaluated_courses: response.progress.evaluated_courses,
            pending_courses: response.progress.pending_courses,
        },
    }
}

fn map_evaluation_course(
    course: domain::EvaluationCourse,
    target_counts: &HashMap<BridgeEvaluationSubmitTarget, usize>,
) -> BridgeEvaluationCourse {
    let mut submit_eligibility = map_action_eligibility(course.submit_eligibility);
    let submit_target = course.submit_target.and_then(map_evaluation_target);
    let allowed_target_is_consistent = submit_target.as_ref().is_some_and(|target| {
        !course.is_evaluated
            && !course.kcmc.trim().is_empty()
            && !course.bpmc.trim().is_empty()
            && course.id == evaluation_course_id(target)
            && target_counts.get(target) == Some(&1)
    });
    let submit_target = match submit_eligibility {
        BridgeActionEligibility::Allowed if allowed_target_is_consistent => submit_target,
        BridgeActionEligibility::Denied | BridgeActionEligibility::Unknown
            if submit_target.is_none() =>
        {
            None
        }
        _ => {
            submit_eligibility = BridgeActionEligibility::Unknown;
            None
        }
    };
    BridgeEvaluationCourse {
        id: course.id,
        kcmc: course.kcmc,
        bpmc: course.bpmc,
        is_evaluated: course.is_evaluated,
        submit_eligibility,
        submit_target,
    }
}

fn evaluation_course_id(target: &BridgeEvaluationSubmitTarget) -> String {
    format!(
        "{}_{}_{}_{}",
        target.rwid,
        target.wjid,
        target.kcdm,
        target.bpdm.as_deref().unwrap_or_default(),
    )
}

fn map_evaluation_target(
    target: domain::EvaluationSubmitTarget,
) -> Option<BridgeEvaluationSubmitTarget> {
    let required = [&target.rwid, &target.wjid, &target.kcdm];
    if required
        .into_iter()
        .any(|value| value.is_empty() || value.trim() != value)
    {
        return None;
    }
    let bpdm = match target.bpdm {
        None => None,
        Some(value) if value.is_empty() => None,
        Some(value) if value.trim() == value => Some(value),
        Some(_) => return None,
    };
    Some(BridgeEvaluationSubmitTarget {
        rwid: target.rwid,
        wjid: target.wjid,
        kcdm: target.kcdm,
        bpdm,
    })
}

fn normalize_evaluation_target_identity(
    target: domain::EvaluationSubmitTarget,
) -> Option<BridgeEvaluationSubmitTarget> {
    let rwid = target.rwid.trim().to_owned();
    let wjid = target.wjid.trim().to_owned();
    let kcdm = target.kcdm.trim().to_owned();
    if rwid.is_empty() || wjid.is_empty() || kcdm.is_empty() {
        return None;
    }
    let bpdm = target
        .bpdm
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty());
    Some(BridgeEvaluationSubmitTarget {
        rwid,
        wjid,
        kcdm,
        bpdm,
    })
}

fn map_action_eligibility(value: domain::ActionEligibility) -> BridgeActionEligibility {
    match value {
        domain::ActionEligibility::Allowed => BridgeActionEligibility::Allowed,
        domain::ActionEligibility::Denied => BridgeActionEligibility::Denied,
        domain::ActionEligibility::Unknown => BridgeActionEligibility::Unknown,
    }
}
