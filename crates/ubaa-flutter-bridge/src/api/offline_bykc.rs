//! 博雅只读缓存类型不包含学校资格或坐标，在线仍沿原 DTO。
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, BridgeRouteDecision, catch_panic,
    disposed_error, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use super::read::{
    BridgeBykcChosenCourse, BridgeBykcCourse, BridgeBykcCourseCategory, BridgeBykcCoursePage,
    BridgeBykcCourseStatus, BridgeBykcCourseSubCategory, BridgeBykcStatistics,
    BridgeBykcUserProfile, map_bykc_category, map_bykc_chosen_courses, map_bykc_course,
    map_bykc_course_page, map_bykc_profile, map_bykc_statistics, map_bykc_status,
    map_bykc_subcategory,
};
use ubaa_core::facade as core;

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcCourse {
    pub id: i64,
    pub course_name: String,
    pub course_position: Option<String>,
    pub course_teacher: Option<String>,
    pub course_start_date: Option<String>,
    pub course_end_date: Option<String>,
    pub course_select_start_date: Option<String>,
    pub course_select_end_date: Option<String>,
    pub course_cancel_end_date: Option<String>,
    pub course_max_count: Option<i32>,
    pub course_current_count: Option<i32>,
    pub status: BridgeBykcCourseStatus,
    pub selected: Option<bool>,
}
fn map_cached_bykc_course(v: core::CachedBykcCourse) -> BridgeCachedBykcCourse {
    BridgeCachedBykcCourse {
        id: v.id,
        course_name: v.course_name,
        course_position: v.course_position,
        course_teacher: v.course_teacher,
        course_start_date: v.course_start_date,
        course_end_date: v.course_end_date,
        course_select_start_date: v.course_select_start_date,
        course_select_end_date: v.course_select_end_date,
        course_cancel_end_date: v.course_cancel_end_date,
        course_max_count: v.course_max_count,
        course_current_count: v.course_current_count,
        status: map_bykc_status(v.status),
        selected: v.selected,
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcChosenCourse {
    pub id: i64,
    pub course_id: i64,
    pub course_name: String,
    pub course_position: Option<String>,
    pub course_teacher: Option<String>,
    pub course_start_date: Option<String>,
    pub course_end_date: Option<String>,
    pub select_date: Option<String>,
    pub course_cancel_end_date: Option<String>,
    pub category: Option<BridgeBykcCourseCategory>,
    pub sub_category: Option<BridgeBykcCourseSubCategory>,
    pub checkin: Option<i32>,
    pub score: Option<i32>,
    pub pass: Option<i32>,
    pub course_sign_type: Option<i32>,
    pub sign_window: Option<BridgeCachedBykcSignWindow>,
}
fn map_cached_bykc_chosen_course(v: core::CachedBykcChosenCourse) -> BridgeCachedBykcChosenCourse {
    BridgeCachedBykcChosenCourse {
        id: v.id,
        course_id: v.course_id,
        course_name: v.course_name,
        course_position: v.course_position,
        course_teacher: v.course_teacher,
        course_start_date: v.course_start_date,
        course_end_date: v.course_end_date,
        select_date: v.select_date,
        course_cancel_end_date: v.course_cancel_end_date,
        category: v.category.map(map_bykc_category),
        sub_category: v.sub_category.map(map_bykc_subcategory),
        checkin: v.checkin,
        score: v.score,
        pass: v.pass,
        course_sign_type: v.course_sign_type,
        sign_window: v.sign_window.map(map_cached_bykc_sign_window),
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcSignWindow {
    pub sign_start_date: Option<String>,
    pub sign_end_date: Option<String>,
    pub sign_out_start_date: Option<String>,
    pub sign_out_end_date: Option<String>,
    pub has_points: bool,
}
fn map_cached_bykc_sign_window(v: core::CachedBykcSignWindow) -> BridgeCachedBykcSignWindow {
    BridgeCachedBykcSignWindow {
        sign_start_date: v.sign_start_date,
        sign_end_date: v.sign_end_date,
        sign_out_start_date: v.sign_out_start_date,
        sign_out_end_date: v.sign_out_end_date,
        has_points: v.has_points,
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcCoursePage {
    pub content: Vec<BridgeCachedBykcCourse>,
    pub total_elements: i32,
    pub total_pages: i32,
    pub size: i32,
    pub number: i32,
}
fn map_cached_bykc_course_page(v: core::CachedBykcCoursePage) -> BridgeCachedBykcCoursePage {
    BridgeCachedBykcCoursePage {
        content: v.content.into_iter().map(map_cached_bykc_course).collect(),
        total_elements: v.total_elements,
        total_pages: v.total_pages,
        size: v.size,
        number: v.number,
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcChosen {
    pub semester_start: String,
    pub semester_end: String,
    pub courses: Vec<BridgeCachedBykcChosenCourse>,
}
fn map_cached_bykc_chosen(v: core::CachedBykcChosen) -> BridgeCachedBykcChosen {
    BridgeCachedBykcChosen {
        semester_start: v.semester_start,
        semester_end: v.semester_end,
        courses: v
            .courses
            .into_iter()
            .map(map_cached_bykc_chosen_course)
            .collect(),
    }
}

#[derive(Clone, Debug)]
pub struct BridgeBykcRefreshState {
    pub fetched_at: i64,
    pub save_error: Option<BridgeCacheFailure>,
    pub semester_start: Option<String>,
    pub semester_end: Option<String>,
}
impl BridgeClient {
    async fn refresh_bykc_record(
        &self,
        cache: &BridgeOfflineCache,
        query: core::BykcCacheQuery,
    ) -> Result<core::OfflineRefresh<core::BykcReadData>, BridgeError> {
        catch_panic(async {
            let mut guard = self.inner.lock().await;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            client
                .refresh_cached_bykc(&cache.cache, query)
                .await
                .map_err(offline_read_error)
        })
        .await
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcProfileRecord {
    pub data: BridgeBykcUserProfile,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcProfileRefresh {
    pub data: BridgeBykcUserProfile,
    pub route: BridgeRouteDecision,
    pub state: BridgeBykcRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络本地读取，空范围返回 None。
    ///
    /// # Errors
    /// 账号关闭、范围无效或记录损坏返回稳定错误。
    pub async fn read_bykc_profile(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedBykcProfileRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_bykc(route.into(), &core::BykcCacheQuery::Profile)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::BykcProfile(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedBykcProfileRecord {
                        data: map_bykc_profile(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 原在线查询及只读持久化；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误与账号退出屏障。
    pub async fn bykc_profile_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeBykcProfileRefresh, BridgeError> {
        let result = self
            .refresh_bykc_record(cache, core::BykcCacheQuery::Profile)
            .await?;
        let core::BykcReadData::Profile(data) = result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeBykcProfileRefresh {
            data: map_bykc_profile(data),
            route: map_route(result.resolution),
            state: BridgeBykcRefreshState {
                fetched_at: result.fetched_at,
                save_error: result.save_error.map(Into::into),
                semester_start: None,
                semester_end: None,
            },
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcCoursesRecord {
    pub data: BridgeCachedBykcCoursePage,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcCoursesRefresh {
    pub data: BridgeBykcCoursePage,
    pub route: BridgeRouteDecision,
    pub state: BridgeBykcRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络本地读取，空范围返回 None。
    ///
    /// # Errors
    /// 账号关闭、范围无效或记录损坏返回稳定错误。
    pub async fn read_bykc_courses(
        &self,
        route: BridgeConnectionMode,
        page: i32,
        size: i32,
        all: bool,
    ) -> Result<Option<BridgeCachedBykcCoursesRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_bykc(
                    route.into(),
                    &core::BykcCacheQuery::Courses { page, size, all },
                )
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::BykcCourses(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedBykcCoursesRecord {
                        data: map_cached_bykc_course_page(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 原在线查询及只读持久化；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误与账号退出屏障。
    pub async fn bykc_courses_cached(
        &self,
        cache: &BridgeOfflineCache,
        page: i32,
        size: i32,
        all: bool,
    ) -> Result<BridgeBykcCoursesRefresh, BridgeError> {
        let result = self
            .refresh_bykc_record(cache, core::BykcCacheQuery::Courses { page, size, all })
            .await?;
        let core::BykcReadData::Courses(data) = result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeBykcCoursesRefresh {
            data: map_bykc_course_page(data),
            route: map_route(result.resolution),
            state: BridgeBykcRefreshState {
                fetched_at: result.fetched_at,
                save_error: result.save_error.map(Into::into),
                semester_start: None,
                semester_end: None,
            },
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcDetailRecord {
    pub data: BridgeCachedBykcCourse,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcDetailRefresh {
    pub data: BridgeBykcCourse,
    pub route: BridgeRouteDecision,
    pub state: BridgeBykcRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络本地读取，空范围返回 None。
    ///
    /// # Errors
    /// 账号关闭、范围无效或记录损坏返回稳定错误。
    pub async fn read_bykc_detail(
        &self,
        route: BridgeConnectionMode,
        course_id: i64,
    ) -> Result<Option<BridgeCachedBykcDetailRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_bykc(route.into(), &core::BykcCacheQuery::Detail { course_id })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::BykcDetail(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedBykcDetailRecord {
                        data: map_cached_bykc_course(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 原在线查询及只读持久化；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误与账号退出屏障。
    pub async fn bykc_detail_cached(
        &self,
        cache: &BridgeOfflineCache,
        course_id: i64,
    ) -> Result<BridgeBykcDetailRefresh, BridgeError> {
        let result = self
            .refresh_bykc_record(cache, core::BykcCacheQuery::Detail { course_id })
            .await?;
        let core::BykcReadData::Detail(data) = result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeBykcDetailRefresh {
            data: map_bykc_course(data),
            route: map_route(result.resolution),
            state: BridgeBykcRefreshState {
                fetched_at: result.fetched_at,
                save_error: result.save_error.map(Into::into),
                semester_start: None,
                semester_end: None,
            },
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcChosenRecord {
    pub data: BridgeCachedBykcChosen,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcChosenRefresh {
    pub data: Vec<BridgeBykcChosenCourse>,
    pub route: BridgeRouteDecision,
    pub state: BridgeBykcRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络本地读取，空范围返回 None。
    ///
    /// # Errors
    /// 账号关闭、范围无效或记录损坏返回稳定错误。
    pub async fn read_bykc_chosen(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedBykcChosenRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_bykc(route.into(), &core::BykcCacheQuery::Chosen)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::BykcChosen(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedBykcChosenRecord {
                        data: map_cached_bykc_chosen(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 原在线查询及只读持久化；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误与账号退出屏障。
    pub async fn bykc_chosen_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeBykcChosenRefresh, BridgeError> {
        let result = self
            .refresh_bykc_record(cache, core::BykcCacheQuery::Chosen)
            .await?;
        let core::BykcReadData::Chosen {
            semester_start,
            semester_end,
            courses: data,
        } = result.data
        else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeBykcChosenRefresh {
            data: map_bykc_chosen_courses(data),
            route: map_route(result.resolution),
            state: BridgeBykcRefreshState {
                fetched_at: result.fetched_at,
                save_error: result.save_error.map(Into::into),
                semester_start: Some(semester_start),
                semester_end: Some(semester_end),
            },
        })
    }
}

#[derive(Clone, Debug)]
pub struct BridgeCachedBykcStatisticsRecord {
    pub data: BridgeBykcStatistics,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
#[derive(Clone, Debug)]
pub struct BridgeBykcStatisticsRefresh {
    pub data: BridgeBykcStatistics,
    pub route: BridgeRouteDecision,
    pub state: BridgeBykcRefreshState,
}
impl BridgeOfflineCache {
    /// 无网络本地读取，空范围返回 None。
    ///
    /// # Errors
    /// 账号关闭、范围无效或记录损坏返回稳定错误。
    pub async fn read_bykc_statistics(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedBykcStatisticsRecord>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_bykc(route.into(), &core::BykcCacheQuery::Statistics)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::BykcStatistics(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedBykcStatisticsRecord {
                        data: map_bykc_statistics(data),
                        source_route: record.scope.route.into(),
                        fetched_at: record.fetched_at,
                        complete: record.completeness == core::CacheCompleteness::Complete,
                    })
                })
                .transpose()
        })
        .await
    }
}
impl BridgeClient {
    /// 原在线查询及只读持久化；待确认写意图阻止隐式恢复。
    ///
    /// # Errors
    /// 保留原业务错误与账号退出屏障。
    pub async fn bykc_statistics_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeBykcStatisticsRefresh, BridgeError> {
        let result = self
            .refresh_bykc_record(cache, core::BykcCacheQuery::Statistics)
            .await?;
        let core::BykcReadData::Statistics(data) = result.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        Ok(BridgeBykcStatisticsRefresh {
            data: map_bykc_statistics(data),
            route: map_route(result.resolution),
            state: BridgeBykcRefreshState {
                fetched_at: result.fetched_at,
                save_error: result.save_error.map(Into::into),
                semester_start: None,
                semester_end: None,
            },
        })
    }
}
#[cfg(test)]
mod tests {
    use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};
    use crate::api::{client::*, offline::BridgeOfflineCache};
    use ubaa_core::facade as core;
    #[tokio::test]
    async fn 博雅本地查询不等待网络锁并保留页范围与退出屏障() {
        let root = std::env::temp_dir().join(format!("ubaa-bykc-cache-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let mut repo = core::OfflineRepository::open(
            &root,
            account,
            core::CacheKey::new([8; 32]),
            core::CacheLimits::default(),
        )
        .unwrap();
        let ticket = repo
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: core::CacheQuery::BykcCourses {
                    page: 1,
                    size: 20,
                    all: true,
                },
            })
            .unwrap();
        repo.publish(
            &ticket,
            core::CachePayload::BykcCourses(core::CachedBykcCoursePage {
                content: vec![core::CachedBykcCourse {
                    id: 42,
                    course_name: "合成课程".into(),
                    ..Default::default()
                }],
                number: 0,
                size: 20,
                total_pages: 2,
                total_elements: 21,
            }),
            123,
            core::CacheCompleteness::Complete,
        )
        .unwrap();
        drop(repo);
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic".into(),
            vec![8; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let saved = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.read_bykc_courses(BridgeConnectionMode::Direct, 1, 20, true),
        )
        .await
        .unwrap()
        .unwrap()
        .unwrap();
        assert_eq!(saved.data.content[0].id, 42);
        assert_eq!(saved.data.number, 0);
        assert_eq!(saved.data.total_pages, 2);
        assert!(
            cache
                .read_bykc_courses(BridgeConnectionMode::Direct, 2, 20, true)
                .await
                .unwrap()
                .is_none()
        );
        assert!(
            cache
                .read_bykc_courses(BridgeConnectionMode::WebVpn, 1, 20, true)
                .await
                .unwrap()
                .is_none()
        );
        drop(guard);
        check_pending(&client, &cache).await;
        cache.deactivate().await.unwrap();
        assert_eq!(
            cache
                .read_bykc_courses(BridgeConnectionMode::Direct, 1, 20, true)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::AuthenticationRequired
        );
        drop(cache);
        drop(client);
        let _ = std::fs::remove_dir_all(root);
    }
    async fn check_pending(client: &BridgeClient, cache: &BridgeOfflineCache) {
        client.write_intents.lock().await.insert(
            "synthetic".into(),
            PendingEntry {
                request: PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 42 }),
                expires_at: i64::MAX,
                resolved_route: BridgeConnectionMode::Direct,
                conflict_key: "synthetic".into(),
            },
        );
        assert_eq!(
            client
                .bykc_courses_cached(cache, 1, 20, true)
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(client.write_intents.lock().await.len(), 1);
    }
}
