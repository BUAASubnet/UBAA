//! 博雅在线资格和只读持久快照分开；不新增学校协议或写路径。
use super::{
    BykcChosenCourse, BykcCourse, BykcCoursePage, BykcStatistics, BykcUserProfile, CachePayload,
    CacheQuery, CacheScope, CachedBykcChosen, ConnectionMode, OfflineCache, OfflineReadError,
    OfflineRefresh, ReadonlyFeature, UbaaClient,
};
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum BykcCacheQuery {
    Profile,
    Courses { page: i32, size: i32, all: bool },
    Catalog { page: i32, size: i32, all: bool },
    FullDetail { course_id: i64 },
    Detail { course_id: i64 },
    Chosen,
    Statistics,
}
impl BykcCacheQuery {
    /// 当前视图与显式分页/详情分别建键，不以响应编号推断下一页。
    #[must_use]
    pub fn cache_query(&self) -> CacheQuery {
        match *self {
            Self::Profile => CacheQuery::BykcProfile,
            Self::Courses { page, size, all } | Self::Catalog { page, size, all } => {
                CacheQuery::BykcCourses { page, size, all }
            }
            Self::Detail { course_id } | Self::FullDetail { course_id } => {
                CacheQuery::BykcDetail { course_id }
            }
            Self::Chosen => CacheQuery::BykcChosen,
            Self::Statistics => CacheQuery::BykcStatistics,
        }
    }
}
/// 在线结果保留原资格；持久化只能经显式白名单投影。
#[derive(Clone, Debug)]
pub enum BykcReadData {
    Profile(BykcUserProfile),
    Courses(BykcCoursePage),
    Catalog(super::BykcCourseCatalogPage),
    FullDetail(Box<super::BykcCourseFullDetail>),
    Detail(BykcCourse),
    Chosen {
        semester_start: String,
        semester_end: String,
        courses: Vec<BykcChosenCourse>,
    },
    Statistics(BykcStatistics),
}
impl BykcReadData {
    fn readonly_payload(&self) -> CachePayload {
        match self {
            Self::Profile(v) => CachePayload::BykcProfile(v.clone()),
            Self::Catalog(v) => CachePayload::BykcCourses(v.clone().into()),
            Self::FullDetail(v) => CachePayload::BykcDetail(v.course.clone().into()),
            Self::Courses(v) => CachePayload::BykcCourses(v.clone().into()),
            Self::Detail(v) => CachePayload::BykcDetail(v.clone().into()),
            Self::Chosen {
                semester_start,
                semester_end,
                courses,
            } => CachePayload::BykcChosen(CachedBykcChosen {
                semester_start: semester_start.clone(),
                semester_end: semester_end.clone(),
                courses: courses.iter().cloned().map(Into::into).collect(),
            }),
            Self::Statistics(v) => CachePayload::BykcStatistics(v.clone()),
        }
    }
}
impl UbaaClient {
    /// 身份核对后沿原查询实现读取，成功替换当前精确范围。
    ///
    /// # Errors
    /// 原学校错误、身份不符与退出栅栏保持；仅本地保存失败可以降级在线显示。
    pub async fn refresh_cached_bykc(
        &mut self,
        cache: &OfflineCache,
        query: BykcCacheQuery,
    ) -> Result<OfflineRefresh<BykcReadData>, OfflineReadError> {
        let refresh = self
            .prepare_cached_refresh(cache, ReadonlyFeature::Bykc, query.cache_query())
            .await?;
        let resolution = refresh.resolution;
        let runtime = self.runtime_for(resolution.mode);
        let result = query.read(runtime).await;
        let data = refresh.read_result(self.finish_routed(resolution, result))?;
        refresh
            .finish(data, true, BykcReadData::readonly_payload)
            .map(|value| value.result)
    }
}
impl OfflineCache {
    /// 独立本地读取，不访问网络客户端或授予学校写资格。
    ///
    /// # Errors
    /// 参数、退出或损坏返回稳定本地错误。
    pub fn read_bykc(
        &self,
        route: ConnectionMode,
        query: &BykcCacheQuery,
    ) -> super::CacheResult<Option<super::CacheRecord>> {
        self.read(
            &CacheScope {
                route,
                query: query.cache_query(),
            },
            chrono::Utc::now().timestamp(),
        )
    }
}

impl BykcCacheQuery {
    async fn read(
        self,
        runtime: &mut crate::runtime::ClientRuntime,
    ) -> crate::error::Result<BykcReadData> {
        match self {
            BykcCacheQuery::Catalog { page, size, all } => {
                crate::features::bykc::get_course_catalog(runtime, page, size, all)
                    .await
                    .map(BykcReadData::Catalog)
            }
            BykcCacheQuery::FullDetail { course_id } => {
                crate::features::bykc::get_course_full_detail(runtime, course_id)
                    .await
                    .map(|value| BykcReadData::FullDetail(Box::new(value)))
            }
            BykcCacheQuery::Profile => crate::features::bykc::get_profile(runtime)
                .await
                .map(BykcReadData::Profile),
            BykcCacheQuery::Courses { page, size, all } => {
                crate::features::bykc::get_courses(runtime, page, size, all)
                    .await
                    .map(BykcReadData::Courses)
            }
            BykcCacheQuery::Detail { course_id } => {
                crate::features::bykc::get_course_detail(runtime, course_id)
                    .await
                    .map(BykcReadData::Detail)
            }
            BykcCacheQuery::Chosen => crate::features::bykc::get_chosen_courses_observed(runtime)
                .await
                .map(
                    |(semester_start, semester_end, courses)| BykcReadData::Chosen {
                        semester_start,
                        semester_end,
                        courses,
                    },
                ),
            BykcCacheQuery::Statistics => crate::features::bykc::get_statistics(runtime)
                .await
                .map(BykcReadData::Statistics),
        }
    }
}
