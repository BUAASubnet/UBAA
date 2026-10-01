//! 独立目录与完整详情入口，保持旧列表及详情合同。

use super::super::client::UbaaClient;
use super::super::routing::{invalid_input, routed_error};
use super::super::types::{Operation, RoutedResult};
use crate::domain::{BykcCourseCatalogPage, BykcCourseFullDetail, ReadonlyFeature};

impl UbaaClient {
    /// 查询含类别和校区的课程目录。
    ///
    /// # Errors
    /// 参数、路线、会话或上游读取失败时返回错误。
    pub async fn bykc_course_catalog(
        &mut self,
        page: i32,
        size: i32,
        all: bool,
    ) -> RoutedResult<BykcCourseCatalogPage> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        if page <= 0 || size <= 0 {
            return Err(routed_error(
                invalid_input("页码和每页数量必须为正数"),
                resolution,
            ));
        }
        let result = crate::features::bykc::get_course_catalog(
            self.runtime_for(resolution.mode),
            page,
            size,
            all,
        )
        .await;
        self.finish_routed(resolution, result)
    }

    /// 查询完整详情，已选补查与主请求共用一次解析的路线。
    ///
    /// # Errors
    /// 参数、路线、会话、主请求或已选补查失败时返回错误。
    pub async fn bykc_course_full_detail(&mut self, id: i64) -> RoutedResult<BykcCourseFullDetail> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Bykc))?;
        if id <= 0 {
            return Err(routed_error(
                invalid_input("课程标识必须为正数"),
                resolution,
            ));
        }
        let result =
            crate::features::bykc::get_course_full_detail(self.runtime_for(resolution.mode), id)
                .await;
        self.finish_routed(resolution, result)
    }
}
