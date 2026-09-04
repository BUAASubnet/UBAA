//! 用户、博雅、场馆、评教、图书馆与阳光打卡只读入口。

use crate::domain::{
    BykcChosenCourse, BykcCourse, BykcCoursePage, BykcStatistics, BykcUserProfile, CgyyDayInfo,
    CgyyLockCode, CgyyOrder, CgyyOrdersPage, CgyyPurposeType, CgyyPurposeTypes, CgyyVenueSite,
    ConnectionMode, EvaluationCoursesResponse, LibBookArea, LibBookAreaDetail, LibBookBookingsPage,
    LibBookLibrary, LibBookSeat, ReadonlyFeature, UserProfile, YgdkOverview, YgdkRecordsPage,
};
use crate::features::user;

use super::super::client::UbaaClient;
use super::super::routing::{invalid_input, routed_error};
use super::super::types::{CallerPinned, Operation, RoutedResult};

impl UbaaClient {
    /// 通过默认路线策略获取用户中心资料。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn get_user_info(&mut self) -> RoutedResult<UserProfile> {
        let resolution = self.resolve_operation(Operation::User)?;
        let result = {
            let (runtime, auth) = self.route_parts_for(resolution.mode);
            let mut clear_workflow = || auth.clear();
            user::get_user_info(runtime, &mut clear_workflow).await
        };
        self.finish_routed(resolution, result)
    }

    /// 查询博雅用户资料。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn bykc_profile(&mut self) -> RoutedResult<BykcUserProfile> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = crate::features::bykc::get_profile(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 查询博雅课程分页。
    ///
    /// # Errors
    ///
    /// 参数无效，或路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn bykc_courses(
        &mut self,
        page: i32,
        size: i32,
        all: bool,
    ) -> RoutedResult<BykcCoursePage> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        if page <= 0 || size <= 0 {
            return Err(routed_error(
                invalid_input("页码和每页数量必须为正数"),
                resolution,
            ));
        }
        let result =
            crate::features::bykc::get_courses(self.runtime_for(resolution.mode), page, size, all)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 查询博雅课程详情。
    ///
    /// # Errors
    ///
    /// 参数无效，或路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn bykc_course_detail(&mut self, id: i64) -> RoutedResult<BykcCourse> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        if id <= 0 {
            return Err(routed_error(
                invalid_input("课程标识必须为正数"),
                resolution,
            ));
        }
        let result =
            crate::features::bykc::get_course_detail(self.runtime_for(resolution.mode), id).await;
        self.finish_routed(resolution, result)
    }

    /// 查询博雅已选课程。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn bykc_chosen_courses(&mut self) -> RoutedResult<Vec<BykcChosenCourse>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result =
            crate::features::bykc::get_chosen_courses(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 查询博雅修读统计。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn bykc_statistics(&mut self) -> RoutedResult<BykcStatistics> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        let result = crate::features::bykc::get_statistics(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 查询全部评教课程。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Evaluation))?;
        let result = crate::features::evaluation::get_all(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 查询场馆站点。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn cgyy_sites(&mut self) -> RoutedResult<Vec<CgyyVenueSite>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "sites.list");
        let result = crate::features::cgyy::get_sites(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 查询场馆用途类型。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn cgyy_purpose_types(&mut self) -> RoutedResult<Vec<CgyyPurposeType>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "purposes.list");
        let result =
            crate::features::cgyy::get_purpose_types(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 查询场馆用途并保留上游或静态回退来源诊断。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn cgyy_purpose_types_diagnostics(&mut self) -> RoutedResult<CgyyPurposeTypes> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        let result =
            crate::features::cgyy::get_purpose_types_with_source(self.runtime_for(resolution.mode))
                .await;
        self.finish_routed(
            resolution,
            result.map(|(items, source)| CgyyPurposeTypes { items, source }),
        )
    }

    /// 查询场馆日期可用性。
    ///
    /// # Errors
    ///
    /// 参数无效，或路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn cgyy_day_info(&mut self, site_id: i32, date: &str) -> RoutedResult<CgyyDayInfo> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "day.info");
        if site_id <= 0 || date.trim().is_empty() {
            return Err(routed_error(
                invalid_input("场馆站点和日期不能为空"),
                resolution,
            ));
        }
        let result =
            crate::features::cgyy::get_day_info(self.runtime_for(resolution.mode), site_id, date)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 查询我的场馆订单。
    ///
    /// # Errors
    ///
    /// 参数无效，或路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn cgyy_orders(&mut self, page: i32, size: i32) -> RoutedResult<CgyyOrdersPage> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "orders.list");
        if page < 0 || size <= 0 {
            return Err(routed_error(invalid_input("分页参数无效"), resolution));
        }
        let result =
            crate::features::cgyy::get_orders(self.runtime_for(resolution.mode), page, size).await;
        self.finish_routed(resolution, result)
    }

    /// 在调用方显式固定的已认证路线查询我的场馆订单，不执行策略解析或 Auto 回退。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、指定路线未认证、参数无效或上游请求失败时返回错误。
    pub async fn cgyy_orders_on_route(
        &mut self,
        route: ConnectionMode,
        page: i32,
        size: i32,
    ) -> crate::error::Result<CallerPinned<CgyyOrdersPage>> {
        self.guard_caller_pinned_route(route)?;
        self.log_cgyy_pinned_route(route, "orders.list");
        if page < 0 || size <= 0 {
            return Err(invalid_input("分页参数无效"));
        }
        let result = crate::features::cgyy::get_orders(self.runtime_for(route), page, size).await;
        self.finish_caller_pinned(route, result)
    }

    /// 查询场馆订单详情。
    ///
    /// # Errors
    ///
    /// 参数无效，或路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn cgyy_order_detail(&mut self, id: i32) -> RoutedResult<CgyyOrder> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "orders.detail");
        if id <= 0 {
            return Err(routed_error(
                invalid_input("订单标识必须为正数"),
                resolution,
            ));
        }
        let result =
            crate::features::cgyy::get_order_detail(self.runtime_for(resolution.mode), id).await;
        self.finish_routed(resolution, result)
    }

    /// 在调用方显式固定的已认证路线查询场馆订单详情，不执行策略解析或 Auto 回退。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、指定路线未认证、参数无效或上游请求失败时返回错误。
    pub async fn cgyy_order_detail_on_route(
        &mut self,
        route: ConnectionMode,
        id: i32,
    ) -> crate::error::Result<CallerPinned<CgyyOrder>> {
        self.guard_caller_pinned_route(route)?;
        self.log_cgyy_pinned_route(route, "orders.detail");
        if id <= 0 {
            return Err(invalid_input("订单标识必须为正数"));
        }
        let result = crate::features::cgyy::get_order_detail(self.runtime_for(route), id).await;
        self.finish_caller_pinned(route, result)
    }

    /// 查询场馆订单锁码。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn cgyy_lock_code(&mut self) -> RoutedResult<CgyyLockCode> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Cgyy))?;
        self.log_cgyy_route(resolution, "orders.lock_code");
        let result = crate::features::cgyy::get_lock_code(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 查询图书馆楼馆列表。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn libbook_libraries(&mut self, day: &str) -> RoutedResult<Vec<LibBookLibrary>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result =
            crate::features::libbook::get_libraries(self.runtime_for(resolution.mode), day).await;
        self.finish_routed(resolution, result)
    }

    /// 查询图书馆分区列表。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn libbook_areas(
        &mut self,
        premises_id: &str,
        storey_id: Option<&str>,
        day: &str,
    ) -> RoutedResult<Vec<LibBookArea>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = crate::features::libbook::get_areas(
            self.runtime_for(resolution.mode),
            premises_id,
            storey_id,
            day,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 查询图书馆分区详情。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn libbook_area_detail(&mut self, area_id: &str) -> RoutedResult<LibBookAreaDetail> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result =
            crate::features::libbook::get_area_detail(self.runtime_for(resolution.mode), area_id)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 查询图书馆座位列表。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn libbook_seats(
        &mut self,
        area_id: &str,
        day: &str,
        start_time: &str,
        end_time: &str,
    ) -> RoutedResult<Vec<LibBookSeat>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result = crate::features::libbook::get_seats(
            self.runtime_for(resolution.mode),
            area_id,
            day,
            start_time,
            end_time,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 查询当前用户的图书馆预约记录。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn libbook_bookings(
        &mut self,
        page: i32,
        limit: i32,
    ) -> RoutedResult<LibBookBookingsPage> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::LibBook))?;
        let result =
            crate::features::libbook::get_bookings(self.runtime_for(resolution.mode), page, limit)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 查询阳光打卡概览。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn ygdk_overview(&mut self) -> RoutedResult<YgdkOverview> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ygdk))?;
        let result = crate::features::ygdk::get_overview(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 在调用方固定的已认证路线查询阳光打卡概览，不执行 Auto 探测或回退。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、指定路线未认证或上游读取失败时返回错误。
    pub async fn ygdk_overview_on_route(
        &mut self,
        route: ConnectionMode,
    ) -> crate::error::Result<CallerPinned<YgdkOverview>> {
        self.guard_caller_pinned_route(route)?;
        let result = crate::features::ygdk::get_overview(self.runtime_for(route)).await;
        self.finish_caller_pinned(route, result)
    }

    /// 查询阳光打卡历史记录。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn ygdk_records(&mut self, page: i32, size: i32) -> RoutedResult<YgdkRecordsPage> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Ygdk))?;
        let result =
            crate::features::ygdk::get_records(self.runtime_for(resolution.mode), page, size).await;
        self.finish_routed(resolution, result)
    }

    /// 在调用方固定的已认证路线查询阳光打卡记录，不执行 Auto 探测或回退。
    ///
    /// # Errors
    ///
    /// 会话所有权失效、指定路线未认证、分页无效或上游读取失败时返回错误。
    pub async fn ygdk_records_on_route(
        &mut self,
        route: ConnectionMode,
        page: i32,
        size: i32,
    ) -> crate::error::Result<CallerPinned<YgdkRecordsPage>> {
        self.guard_caller_pinned_route(route)?;
        let result = crate::features::ygdk::get_records(self.runtime_for(route), page, size).await;
        self.finish_caller_pinned(route, result)
    }
}
