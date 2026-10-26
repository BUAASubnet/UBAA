//! 非幂等提交后的只读核对始终绑定调用方确认的路线。
use crate::domain::{BykcChosenCourse, ConnectionMode, LibBookBookingsPage, SigninClass};
use crate::error::Result;
use crate::facade::{CallerPinned, UbaaClient};

impl UbaaClient {
    /// 读取指定路线的博雅已选课程，不执行 Auto 回退。
    /// # Errors
    /// 原路线认证、会话修订、请求或解析失败时返回原错误。
    pub async fn bykc_chosen_courses_on_route(
        &mut self,
        route: ConnectionMode,
    ) -> Result<CallerPinned<Vec<BykcChosenCourse>>> {
        self.guard_caller_pinned_route(route)?;
        let result = crate::features::bykc::get_chosen_courses(self.runtime_for(route)).await;
        self.finish_caller_pinned(route, result)
    }
    /// 读取指定路线的图书馆预约记录，不执行 Auto 回退。
    /// # Errors
    /// 原路线认证、会话修订、请求或解析失败时返回原错误。
    pub async fn libbook_bookings_on_route(
        &mut self,
        route: ConnectionMode,
        page: i32,
        limit: i32,
    ) -> Result<CallerPinned<LibBookBookingsPage>> {
        self.guard_caller_pinned_route(route)?;
        let result =
            crate::features::libbook::get_bookings(self.runtime_for(route), page, limit).await;
        self.finish_caller_pinned(route, result)
    }
    /// 读取指定路线的今日课堂签到状态，不执行 Auto 回退。
    /// # Errors
    /// 原路线认证、会话修订、请求或解析失败时返回原错误。
    pub async fn signin_today_on_route(
        &mut self,
        route: ConnectionMode,
    ) -> Result<CallerPinned<Vec<SigninClass>>> {
        self.guard_caller_pinned_route(route)?;
        let result = crate::features::signin::get_today(self.runtime_for(route)).await;
        self.finish_caller_pinned(route, result)
    }
}
