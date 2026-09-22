//! SPOC 作业详情与可选提交内容读取。

use super::SpocCredential;
use super::auth::{check_business_response, resolve_required_spoc_result, with_spoc_auth_retry};
use super::list::get_assignments_observed;
use super::parser::{
    DetailRaw, SubmissionRaw, detail_id_mismatch, merge_detail, parse_envelope,
    parse_optional_envelope,
};

/// 作业详情地址。
pub const ASSIGNMENT_DETAIL_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/kczy/queryKczyInfoByid";
/// 用于只读详情补充的提交状态地址。
pub const SUBMISSION_URL: &str = "https://spoc.buaa.edu.cn/spocnewht/kczy/queryXsSubmitKczyInfo";

/// 获取一项只读 SPOC 作业详情。
pub(crate) async fn get_assignment_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: &str,
) -> crate::error::Result<crate::domain::SpocAssignmentDetail> {
    Ok(get_assignment_detail_observed(runtime, assignment_id)
        .await?
        .0)
}

pub(crate) async fn get_assignment_detail_observed(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: &str,
) -> crate::error::Result<(crate::domain::SpocAssignmentDetail, bool)> {
    if assignment_id.trim().is_empty() {
        return Err(crate::error::UbaaError::new(
            crate::error::ErrorCode::InvalidInput,
            crate::error::ErrorKind::Input,
            false,
            "作业标识不能为空",
        ));
    }
    let (assignments, list_complete) = get_assignments_observed(runtime).await?;
    let base = assignments
        .result
        .assignments
        .into_iter()
        .find(|assignment| assignment.assignment_id == assignment_id)
        .ok_or_else(|| {
            crate::error::UbaaError::new(
                crate::error::ErrorCode::UpstreamChanged,
                crate::error::ErrorKind::Upstream,
                false,
                "未找到 SPOC 作业",
            )
        })?;
    get_assignment_detail_for_base(runtime, &base)
        .await
        .map(|(detail, complete)| (detail, list_complete && complete))
}

/// 已核实目标的有界正文与补充读取，不再次扫描全局列表。
pub(crate) async fn get_assignment_detail_for_base(
    runtime: &mut crate::runtime::ClientRuntime,
    base: &crate::domain::SpocAssignmentSummary,
) -> crate::error::Result<(crate::domain::SpocAssignmentDetail, bool)> {
    let assignment_id = &base.assignment_id;
    let detail_id = assignment_id.to_owned();
    let detail_result = with_spoc_auth_retry(runtime, move |runtime, credential| {
        Box::pin(fetch_assignment_detail(
            runtime,
            detail_id.clone(),
            credential,
        ))
    })
    .await;
    let raw = resolve_required_spoc_result(runtime, detail_result).await?;
    if &raw.id != assignment_id {
        return Err(detail_id_mismatch());
    }
    let (submission, submission_complete) = fetch_optional_submission(runtime, assignment_id).await;
    merge_detail(assignment_id, base, &raw, submission.as_ref())
        .map(|detail| (detail, submission_complete))
}

async fn fetch_assignment_detail(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: String,
    credential: &SpocCredential,
) -> crate::error::Result<DetailRaw> {
    let mut url = url::Url::parse(&runtime.url(ASSIGNMENT_DETAIL_URL)?).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC 地址无效",
        )
    })?;
    url.query_pairs_mut().append_pair("id", &assignment_id);
    let token_header = credential.token_header();
    let response = crate::features::get_with_headers(
        runtime,
        url.to_string(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
            ("RoleCode", &credential.role),
        ],
    )
    .await?;
    check_business_response(&response)?;
    parse_envelope(&crate::features::body(&response))
}

async fn fetch_optional_submission(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: &str,
) -> (Option<SubmissionRaw>, bool) {
    let assignment_id = assignment_id.to_owned();
    let result = with_spoc_auth_retry(runtime, move |runtime, credential| {
        Box::pin(fetch_submission(runtime, assignment_id.clone(), credential))
    })
    .await;
    let complete = result.is_ok();
    (result.ok().flatten(), complete)
}

async fn fetch_submission(
    runtime: &mut crate::runtime::ClientRuntime,
    assignment_id: String,
    credential: &SpocCredential,
) -> crate::error::Result<Option<SubmissionRaw>> {
    let mut url = url::Url::parse(&runtime.url(SUBMISSION_URL)?).map_err(|_| {
        crate::error::UbaaError::new(
            crate::error::ErrorCode::UpstreamChanged,
            crate::error::ErrorKind::Upstream,
            false,
            "SPOC 地址无效",
        )
    })?;
    url.query_pairs_mut().append_pair("kczyid", &assignment_id);
    let token_header = credential.token_header();
    let response = crate::features::get_with_headers(
        runtime,
        url.to_string(),
        &[
            ("X-Requested-With", "XMLHttpRequest"),
            ("Token", &token_header),
            ("RoleCode", &credential.role),
        ],
    )
    .await?;
    check_business_response(&response)?;
    parse_optional_envelope(&crate::features::body(&response))
}
