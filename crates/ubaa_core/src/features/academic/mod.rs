//! 根据门户明确身份选择学业系统。
mod gsmis;
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;
pub(crate) use gsmis::{exam_terms, exams, grades, is_term, require_term};

pub(crate) use crate::internal::route_state::StudentKind;

pub(crate) async fn identity(runtime: &mut ClientRuntime) -> Result<StudentKind> {
    crate::features::require_session(runtime)?;
    runtime.ensure_session_revision()?;
    let owner = runtime.feature_state();
    let _guard = owner.academic_identity_read.lock().await;
    let generation = owner.lifecycle_generation();
    if let Some((stored_generation, kind)) = *owner
        .academic_identity
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        && stored_generation == generation
    {
        return Ok(kind);
    }
    let profile = crate::features::campus::get_profile(runtime).await?;
    let kind = match profile.identity.as_str() {
        "本科生" => StudentKind::Undergraduate,
        "研究生" | "硕士研究生" | "博士研究生" => StudentKind::Graduate,
        _ => {
            return Err(UbaaError::new(
                ErrorCode::Unsupported,
                ErrorKind::Upstream,
                false,
                "门户身份暂不支持学业查询",
            ));
        }
    };
    runtime.ensure_session_revision()?;
    *owner
        .academic_identity
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some((generation, kind));
    Ok(kind)
}

#[cfg(all(test, feature = "test-contract"))]
mod tests;
