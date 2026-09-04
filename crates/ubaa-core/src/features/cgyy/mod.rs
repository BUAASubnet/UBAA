//! 场馆预约业务边界。
#![allow(clippy::missing_errors_doc)]

mod auth;
mod captcha;
mod crypto;
mod http;
mod parser;
mod read;
mod sign;
mod write;

#[allow(unused_imports)]
pub use captcha::build_captcha_check_form;
#[allow(unused_imports)]
pub(crate) use captcha::{CgyyCaptchaChallenge, solve_captcha_offset};
#[allow(unused_imports)]
pub use parser::{
    parse_action_result, parse_lock_code, parse_order_detail, parse_orders, parse_sites,
};
pub(crate) use read::{
    get_day_info, get_lock_code, get_order_detail, get_orders, get_purpose_types,
    get_purpose_types_with_source, get_sites,
};
#[allow(unused_imports)]
pub use write::build_submit_form;
pub(crate) use write::{cancel_order, preflight_reservation, submit_reservation};

#[cfg(test)]
mod tests;
