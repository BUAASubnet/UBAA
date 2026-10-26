//! 课表、考试、成绩与空教室只读入口。

use crate::domain::{
    ClassroomQuery, ExamArrangement, GradeData, ReadonlyFeature, Term, TodayClass, Week,
    WeeklySchedule,
};

use super::super::client::UbaaClient;
use super::super::routing::{invalid_input, routed_error};
use super::super::types::{Operation, RoutedResult};

impl UbaaClient {
    /// 通过课表路线策略读取可用学期。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn schedule_terms(&mut self) -> RoutedResult<Vec<Term>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Schedule))?;
        let result = crate::features::schedule::get_terms(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 通过课表路线策略读取一个学期的教学周。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn schedule_weeks(&mut self, term: &str) -> RoutedResult<Vec<Week>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Schedule))?;
        let result =
            crate::features::schedule::get_weeks(self.runtime_for(resolution.mode), term).await;
        self.finish_routed(resolution, result)
    }

    /// 通过课表路线策略读取指定周课表。
    ///
    /// # Errors
    ///
    /// 参数无效，或路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn schedule_week(&mut self, term: &str, week: i32) -> RoutedResult<WeeklySchedule> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Schedule))?;
        if term.trim().is_empty() || week <= 0 {
            return Err(routed_error(
                invalid_input("term and positive week are required"),
                resolution,
            ));
        }
        let result =
            crate::features::schedule::get_week(self.runtime_for(resolution.mode), term, week)
                .await;
        self.finish_routed(resolution, result)
    }

    /// 通过课表路线策略读取今日课表。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn schedule_today(&mut self) -> RoutedResult<Vec<TodayClass>> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Schedule))?;
        let result = crate::features::schedule::get_today(self.runtime_for(resolution.mode)).await;
        self.finish_routed(resolution, result)
    }

    /// 通过考试路线策略读取一个学期的考试安排。
    ///
    /// # Errors
    ///
    /// 参数无效，或路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn exam_arrangement(&mut self, term: &str) -> RoutedResult<ExamArrangement> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Exam))?;
        if term.trim().is_empty() {
            return Err(routed_error(invalid_input("term is required"), resolution));
        }
        let result =
            crate::features::schedule::get_exam(self.runtime_for(resolution.mode), term).await;
        self.finish_routed(resolution, result)
    }

    /// 通过成绩路线策略读取一个学期的成绩。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn grades(&mut self, term: &str) -> RoutedResult<GradeData> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Grades))?;
        let result =
            crate::features::grades::get_grades(self.runtime_for(resolution.mode), term).await;
        self.finish_routed(resolution, result)
    }

    /// 通过空教室路线策略查询可用教室。
    ///
    /// # Errors
    ///
    /// 路线解析、会话校验、上游请求或响应解析失败时返回错误。
    pub async fn classroom_search(
        &mut self,
        campus_id: i32,
        date: &str,
    ) -> RoutedResult<ClassroomQuery> {
        let resolution = self.resolve_operation(Operation::Feature(ReadonlyFeature::Classroom))?;
        let result =
            crate::features::classroom::search(self.runtime_for(resolution.mode), campus_id, date)
                .await;
        self.finish_routed(resolution, result)
    }
}
