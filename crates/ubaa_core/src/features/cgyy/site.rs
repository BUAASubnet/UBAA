//! 场馆预约站点：北京研讨室（cgyy）与杭州校区空间预约（hzsm）。
//!
//! 两个站点是同一厂商产品，签名常量、`/api/login` 和业务信封相同；差异只有基址、
//! SSO 引导与 Cookie 名、`Referer` 和场馆列表参数。杭州依据见
//! `docs/protocol/parity/cgyy.md` 的 2026-11-25 杭州专项记录。

use crate::internal::route_state::{CgyyState, RouteFeatureState};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum CgyySite {
    /// 北京 `cgyy.buaa.edu.cn/venue-zhjs`。
    Beijing,
    /// 杭州 `hzsm.buaa.edu.cn/venue`。
    Hangzhou,
}

impl CgyySite {
    pub(crate) const fn base_url(self) -> &'static str {
        match self {
            Self::Beijing => "https://cgyy.buaa.edu.cn/venue-zhjs-server",
            Self::Hangzhou => "https://hzsm.buaa.edu.cn/venue-server",
        }
    }

    pub(crate) const fn referer(self) -> &'static str {
        match self {
            Self::Beijing => "https://cgyy.buaa.edu.cn/venue-zhjs/mobileReservation",
            Self::Hangzhou => "https://hzsm.buaa.edu.cn/venue/home",
        }
    }

    pub(crate) const fn sso_cookie(self) -> &'static str {
        match self {
            Self::Beijing => "sso_buaa_zhjs_token",
            Self::Hangzhou => "sso_buaa_h3i_token",
        }
    }

    pub(crate) const fn feature_name(self) -> &'static str {
        match self {
            Self::Beijing => "研讨室预约",
            Self::Hangzhou => "杭州空间预约",
        }
    }

    pub(crate) fn state(self, state: &RouteFeatureState) -> &CgyyState {
        match self {
            Self::Beijing => &state.cgyy,
            Self::Hangzhou => &state.hz_cgyy,
        }
    }
}
