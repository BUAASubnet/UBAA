//! 构建于 Core 认证会话之上的校园功能模块。

mod http;

pub mod bykc;
pub mod cgyy;
pub mod classroom;
pub mod evaluation;
pub mod grades;
pub mod judge;
pub mod libbook;
pub mod schedule;
pub mod signin;
pub mod spoc;
pub(crate) use crate::internal::route_state as state;
pub(crate) mod user;
pub mod ygdk;

pub(crate) use http::{
    body, check_response, get_with_headers, get_with_redirects, post_form, post_json,
    require_session,
};

use crate::runtime::ClientRuntime;

pub(crate) fn feature_result<T>(
    runtime: &ClientRuntime,
    data: T,
) -> crate::domain::FeatureResult<T> {
    crate::domain::FeatureResult {
        data,
        resolved_route: runtime.mode(),
    }
}
