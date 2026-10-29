//! 学业缓存的 typed 绑定，不把任意载荷交给宿主。
pub mod baseline;
use super::client::{
    BridgeClient, BridgeConnectionMode, BridgeError, catch_panic, disposed_error, map_route,
};
use super::offline::{
    BridgeCacheFailure, BridgeOfflineCache, cache_error, local_task, offline_read_error,
};
use super::read::{
    BridgeClassroomQuery, BridgeExamArrangement, BridgeGradeData, BridgeRoutedClassroomQuery,
    BridgeRoutedExamArrangement, BridgeRoutedGrades, BridgeRoutedTerms, BridgeRoutedWeeklySchedule,
    BridgeRoutedWeeks, BridgeTerm, BridgeWeek, BridgeWeeklySchedule, map_classroom_query,
    map_exam_arrangement, map_grade_data, map_terms, map_weekly_schedule, map_weeks,
};
use ubaa_core::facade as core;

impl BridgeClient {
    async fn refresh_academic_record(
        &self,
        cache: &BridgeOfflineCache,
        query: core::AcademicQuery,
    ) -> Result<core::OfflineRefresh<core::CachePayload>, BridgeError> {
        catch_panic(async {
            let mut guard = self
                .inner
                .read(Some(crate::api::read_pool::ReadGroup::Academic))
                .await?;
            let client = guard.as_mut().ok_or_else(disposed_error)?;
            self.ensure_recovery_allowed().await?;
            client
                .refresh_cached_academic(&cache.cache, query)
                .await
                .map_err(offline_read_error)
        })
        .await
    }
}

/// 已保存的精确范围，原时间与路线不由当前配置替换。
#[derive(Clone, Debug)]
pub struct BridgeCachedAcademicTerms {
    pub data: Vec<BridgeTerm>,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
/// 本次在线内容与是否成功保存分别返回。
#[derive(Clone, Debug)]
pub struct BridgeAcademicTermsRefresh {
    pub result: BridgeRoutedTerms,
    pub fetched_at: i64,
    pub complete: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
impl BridgeOfflineCache {
    /// 只访问独立本地仓库，不获取网络客户端锁。
    ///
    /// # Errors
    /// 范围无效、账号关闭或存储损坏时返回稳定错误。
    pub async fn read_academic_terms(
        &self,
        route: BridgeConnectionMode,
    ) -> Result<Option<BridgeCachedAcademicTerms>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_academic(route.into(), &core::AcademicQuery::Terms)
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::Terms(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedAcademicTerms {
                        data: map_terms(data),
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
    /// 在原客户端执行已核对的业务读取，保存错误不冒充学校失败。
    ///
    /// # Errors
    /// 身份、认证、业务或退出栅栏错误保持原分类，待确认写操作阻止隐式恢复。
    pub async fn academic_terms_cached(
        &self,
        cache: &BridgeOfflineCache,
    ) -> Result<BridgeAcademicTermsRefresh, BridgeError> {
        let value = self
            .refresh_academic_record(cache, core::AcademicQuery::Terms)
            .await?;
        let core::CachePayload::Terms(data) = value.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        let complete = true;
        Ok(BridgeAcademicTermsRefresh {
            result: BridgeRoutedTerms {
                data: map_terms(data),
                route: map_route(value.resolution),
            },
            fetched_at: value.fetched_at,
            complete,
            save_error: value.save_error.map(Into::into),
        })
    }
}

/// 已保存的精确范围，原时间与路线不由当前配置替换。
#[derive(Clone, Debug)]
pub struct BridgeCachedAcademicWeeks {
    pub data: Vec<BridgeWeek>,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
/// 本次在线内容与是否成功保存分别返回。
#[derive(Clone, Debug)]
pub struct BridgeAcademicWeeksRefresh {
    pub result: BridgeRoutedWeeks,
    pub fetched_at: i64,
    pub complete: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
impl BridgeOfflineCache {
    /// 只访问独立本地仓库，不获取网络客户端锁。
    ///
    /// # Errors
    /// 范围无效、账号关闭或存储损坏时返回稳定错误。
    pub async fn read_academic_weeks(
        &self,
        route: BridgeConnectionMode,
        term: String,
    ) -> Result<Option<BridgeCachedAcademicWeeks>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_academic(route.into(), &core::AcademicQuery::Weeks { term })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::Weeks(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedAcademicWeeks {
                        data: map_weeks(data),
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
    /// 在原客户端执行已核对的业务读取，保存错误不冒充学校失败。
    ///
    /// # Errors
    /// 身份、认证、业务或退出栅栏错误保持原分类，待确认写操作阻止隐式恢复。
    pub async fn academic_weeks_cached(
        &self,
        cache: &BridgeOfflineCache,
        term: String,
    ) -> Result<BridgeAcademicWeeksRefresh, BridgeError> {
        let value = self
            .refresh_academic_record(cache, core::AcademicQuery::Weeks { term })
            .await?;
        let core::CachePayload::Weeks(data) = value.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        let complete = true;
        Ok(BridgeAcademicWeeksRefresh {
            result: BridgeRoutedWeeks {
                data: map_weeks(data),
                route: map_route(value.resolution),
            },
            fetched_at: value.fetched_at,
            complete,
            save_error: value.save_error.map(Into::into),
        })
    }
}

/// 已保存的精确范围，原时间与路线不由当前配置替换。
#[derive(Clone, Debug)]
pub struct BridgeCachedAcademicWeek {
    pub data: BridgeWeeklySchedule,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
/// 本次在线内容与是否成功保存分别返回。
#[derive(Clone, Debug)]
pub struct BridgeAcademicWeekRefresh {
    pub result: BridgeRoutedWeeklySchedule,
    pub fetched_at: i64,
    pub complete: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
impl BridgeOfflineCache {
    /// 只访问独立本地仓库，不获取网络客户端锁。
    ///
    /// # Errors
    /// 范围无效、账号关闭或存储损坏时返回稳定错误。
    pub async fn read_academic_week(
        &self,
        route: BridgeConnectionMode,
        term: String,
        week: i32,
    ) -> Result<Option<BridgeCachedAcademicWeek>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_academic(route.into(), &core::AcademicQuery::Week { term, week })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::Week(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedAcademicWeek {
                        data: map_weekly_schedule(data),
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
    /// 在原客户端执行已核对的业务读取，保存错误不冒充学校失败。
    ///
    /// # Errors
    /// 身份、认证、业务或退出栅栏错误保持原分类，待确认写操作阻止隐式恢复。
    pub async fn academic_week_cached(
        &self,
        cache: &BridgeOfflineCache,
        term: String,
        week: i32,
    ) -> Result<BridgeAcademicWeekRefresh, BridgeError> {
        let value = self
            .refresh_academic_record(cache, core::AcademicQuery::Week { term, week })
            .await?;
        let core::CachePayload::Week(data) = value.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        let complete = true;
        Ok(BridgeAcademicWeekRefresh {
            result: BridgeRoutedWeeklySchedule {
                data: map_weekly_schedule(data),
                route: map_route(value.resolution),
            },
            fetched_at: value.fetched_at,
            complete,
            save_error: value.save_error.map(Into::into),
        })
    }
}

/// 已保存的精确范围，原时间与路线不由当前配置替换。
#[derive(Clone, Debug)]
pub struct BridgeCachedAcademicExams {
    pub data: BridgeExamArrangement,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
/// 本次在线内容与是否成功保存分别返回。
#[derive(Clone, Debug)]
pub struct BridgeAcademicExamsRefresh {
    pub result: BridgeRoutedExamArrangement,
    pub fetched_at: i64,
    pub complete: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
impl BridgeOfflineCache {
    /// 只访问独立本地仓库，不获取网络客户端锁。
    ///
    /// # Errors
    /// 范围无效、账号关闭或存储损坏时返回稳定错误。
    pub async fn read_academic_exams(
        &self,
        route: BridgeConnectionMode,
        term: String,
    ) -> Result<Option<BridgeCachedAcademicExams>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_academic(route.into(), &core::AcademicQuery::Exams { term })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::Exams(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedAcademicExams {
                        data: map_exam_arrangement(data),
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
    /// 在原客户端执行已核对的业务读取，保存错误不冒充学校失败。
    ///
    /// # Errors
    /// 身份、认证、业务或退出栅栏错误保持原分类，待确认写操作阻止隐式恢复。
    pub async fn academic_exams_cached(
        &self,
        cache: &BridgeOfflineCache,
        term: String,
    ) -> Result<BridgeAcademicExamsRefresh, BridgeError> {
        let value = self
            .refresh_academic_record(cache, core::AcademicQuery::Exams { term })
            .await?;
        let core::CachePayload::Exams(data) = value.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        let complete = true;
        Ok(BridgeAcademicExamsRefresh {
            result: BridgeRoutedExamArrangement {
                data: map_exam_arrangement(data),
                route: map_route(value.resolution),
            },
            fetched_at: value.fetched_at,
            complete,
            save_error: value.save_error.map(Into::into),
        })
    }
}

/// 已保存的精确范围，原时间与路线不由当前配置替换。
#[derive(Clone, Debug)]
pub struct BridgeCachedAcademicGrades {
    pub data: BridgeGradeData,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
/// 本次在线内容与是否成功保存分别返回。
#[derive(Clone, Debug)]
pub struct BridgeAcademicGradesRefresh {
    pub result: BridgeRoutedGrades,
    pub fetched_at: i64,
    pub complete: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
impl BridgeOfflineCache {
    /// 只访问独立本地仓库，不获取网络客户端锁。
    ///
    /// # Errors
    /// 范围无效、账号关闭或存储损坏时返回稳定错误。
    pub async fn read_academic_grades(
        &self,
        route: BridgeConnectionMode,
        term: String,
    ) -> Result<Option<BridgeCachedAcademicGrades>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_academic(route.into(), &core::AcademicQuery::Grades { term })
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::Grades(data) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedAcademicGrades {
                        data: map_grade_data(data),
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
    /// 在原客户端执行已核对的业务读取，保存错误不冒充学校失败。
    ///
    /// # Errors
    /// 身份、认证、业务或退出栅栏错误保持原分类，待确认写操作阻止隐式恢复。
    pub async fn academic_grades_cached(
        &self,
        cache: &BridgeOfflineCache,
        term: String,
    ) -> Result<BridgeAcademicGradesRefresh, BridgeError> {
        let value = self
            .refresh_academic_record(cache, core::AcademicQuery::Grades { term })
            .await?;
        let core::CachePayload::Grades(data) = value.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        let complete = true;
        Ok(BridgeAcademicGradesRefresh {
            result: BridgeRoutedGrades {
                data: map_grade_data(data),
                route: map_route(value.resolution),
            },
            fetched_at: value.fetched_at,
            complete,
            save_error: value.save_error.map(Into::into),
        })
    }
}

/// 已保存的精确范围，原时间与路线不由当前配置替换。
#[derive(Clone, Debug)]
pub struct BridgeCachedAcademicClassrooms {
    pub data: BridgeClassroomQuery,
    pub source_route: BridgeConnectionMode,
    pub fetched_at: i64,
    pub complete: bool,
}
/// 本次在线内容与是否成功保存分别返回。
#[derive(Clone, Debug)]
pub struct BridgeAcademicClassroomsRefresh {
    pub result: BridgeRoutedClassroomQuery,
    pub fetched_at: i64,
    pub complete: bool,
    pub save_error: Option<BridgeCacheFailure>,
}
impl BridgeOfflineCache {
    /// 只访问独立本地仓库，不获取网络客户端锁。
    ///
    /// # Errors
    /// 范围无效、账号关闭或存储损坏时返回稳定错误。
    pub async fn read_academic_classrooms(
        &self,
        route: BridgeConnectionMode,
        campus: i32,
        date: String,
    ) -> Result<Option<BridgeCachedAcademicClassrooms>, BridgeError> {
        let cache = self.cache.clone();
        local_task(move || {
            cache
                .read_academic(
                    route.into(),
                    &core::AcademicQuery::Classrooms { campus, date },
                )
                .map_err(cache_error)?
                .map(|record| {
                    let core::CachePayload::Classrooms(payload) = record.payload else {
                        return Err(cache_error(core::CacheError::Corrupt));
                    };
                    Ok(BridgeCachedAcademicClassrooms {
                        data: map_classroom_query(payload),
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
    /// 在原客户端执行已核对的业务读取，保存错误不冒充学校失败。
    ///
    /// # Errors
    /// 身份、认证、业务或退出栅栏错误保持原分类，待确认写操作阻止隐式恢复。
    pub async fn academic_classrooms_cached(
        &self,
        cache: &BridgeOfflineCache,
        campus: i32,
        date: String,
    ) -> Result<BridgeAcademicClassroomsRefresh, BridgeError> {
        let value = self
            .refresh_academic_record(cache, core::AcademicQuery::Classrooms { campus, date })
            .await?;
        let core::CachePayload::Classrooms(payload) = value.data else {
            return Err(cache_error(core::CacheError::Corrupt));
        };
        let complete = payload.code == 0;
        Ok(BridgeAcademicClassroomsRefresh {
            result: BridgeRoutedClassroomQuery {
                data: map_classroom_query(payload),
                route: map_route(value.resolution),
            },
            fetched_at: value.fetched_at,
            complete,
            save_error: value.save_error.map(Into::into),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::super::{client::*, offline::BridgeOfflineCache};
    use crate::api::write::{BridgeBykcCourseRequest, PendingEntry, PendingWrite};
    use ubaa_core::facade as core;
    #[tokio::test]
    async fn 学业本地通道不等待网络锁且保留请求学期和原取得时间() {
        let root =
            std::env::temp_dir().join(format!("ubaa-academic-bridge-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let account = "0123456789abcdef0123456789abcdef";
        let mut repository = core::OfflineRepository::open(
            &root,
            account,
            core::CacheKey::new([3; 32]),
            core::CacheLimits::default(),
        )
        .unwrap();
        let ticket = repository
            .begin_read(core::CacheScope {
                route: core::ConnectionMode::Direct,
                query: core::CacheQuery::Grades {
                    term: "2025-2026-1".into(),
                },
            })
            .unwrap();
        repository
            .publish(
                &ticket,
                core::CachePayload::Grades(core::GradeData {
                    term_code: "2025-2026-1".into(),
                    grades: vec![core::Grade {
                        course_name: Some("合成课程".into()),
                        score: Some("90".into()),
                        ..Default::default()
                    }],
                }),
                123,
                core::CacheCompleteness::Complete,
            )
            .unwrap();
        drop(repository);
        let client = BridgeClient::open(root.to_string_lossy().into()).unwrap();
        let cache = BridgeOfflineCache::open(
            root.to_string_lossy().into(),
            account.into(),
            "synthetic".into(),
            vec![3; 32],
        )
        .await
        .unwrap();
        let guard = client.inner.lock().await;
        let record = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            cache.read_academic_grades(BridgeConnectionMode::Direct, "2025-2026-1".into()),
        )
        .await
        .unwrap()
        .unwrap()
        .unwrap();
        assert_eq!(record.fetched_at, 123);
        assert_eq!(record.data.term_code, "2025-2026-1");
        assert_eq!(record.data.grades[0].score.as_deref(), Some("90"));
        assert!(
            cache
                .read_academic_grades(BridgeConnectionMode::Direct, "2025-2026-2".into())
                .await
                .unwrap()
                .is_none()
        );
        drop(guard);
        client.write_intents.lock().await.insert(
            "synthetic".into(),
            PendingEntry {
                request: PendingWrite::BykcSelect(BridgeBykcCourseRequest { course_id: 1 }),
                expires_at: i64::MAX,
                resolved_route: BridgeConnectionMode::Direct,
                conflict_key: "synthetic".into(),
            },
        );
        assert_eq!(
            client.academic_terms_cached(&cache).await.unwrap_err().code,
            BridgeErrorCode::OperationConflict
        );
        assert_eq!(client.write_intents.lock().await.len(), 1);
        cache.deactivate().await.unwrap();
        assert_eq!(
            cache
                .read_academic_grades(BridgeConnectionMode::Direct, "2025-2026-1".into())
                .await
                .unwrap_err()
                .code,
            BridgeErrorCode::AuthenticationRequired
        );
        drop(cache);
        drop(client);
        let _ = std::fs::remove_dir_all(root);
    }
}
