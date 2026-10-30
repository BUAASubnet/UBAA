//! 显示读取在完整激活、任务、问卷或课程请求之间让位；不用于 strict 写授权。
use super::parser::{
    AuthorityEntry, CourseContext, EvaluationAuthoritySnapshot, canonical_string, parse_course_rows,
};
use super::{is_authentication_error, read};
use crate::{
    domain::{ActionEligibility, EvaluationCoursesResponse},
    error::Result,
    runtime::ClientRuntime,
};
use serde_json::Value;
#[derive(Default)]
enum Stage {
    #[default]
    Activation,
    Tasks,
    Questionnaires,
    Courses,
}
#[derive(Default)]
pub(crate) struct Cursor {
    stage: Stage,
    tasks: Vec<String>,
    task_index: usize,
    forms: Vec<CourseContext>,
    form_index: usize,
    entries: Vec<AuthorityEntry>,
    incomplete: bool,
    pub finished: bool,
    pub error: Option<crate::error::UbaaError>,
    pub completed_course_lists: u32,
}
impl Cursor {
    pub fn complete(&self) -> bool {
        self.finished && !self.incomplete
    }
    pub fn data(&self) -> EvaluationCoursesResponse {
        let mut response =
            EvaluationAuthoritySnapshot::finalize(self.entries.clone()).into_response();
        if !self.complete() {
            for course in &mut response.courses {
                course.submit_eligibility = ActionEligibility::Unknown;
                course.submit_target = None;
            }
        }
        response
    }
    fn finish(&mut self) {
        self.finished = true;
        let mut identities = std::collections::HashSet::new();
        self.incomplete |= self
            .entries
            .iter()
            .any(|entry| entry.course.id.is_empty() || !identities.insert(entry.course.id.clone()));
    }
    fn next_task(&mut self) {
        self.task_index += 1;
        self.forms.clear();
        self.form_index = 0;
        self.stage = Stage::Questionnaires;
        if self.task_index >= self.tasks.len() {
            self.finish();
        }
    }
    pub async fn advance(&mut self, runtime: &mut ClientRuntime) -> Result<()> {
        super::super::require_session(runtime)?;
        match self.stage {
            Stage::Activation => match read::activate(runtime).await {
                Ok(()) => self.stage = Stage::Tasks,
                Err(error) if !is_authentication_error(&error) => {
                    self.incomplete = true;
                    self.error.get_or_insert(error);
                    self.finish();
                }
                Err(error) => return Err(error),
            },
            Stage::Tasks => self.read_tasks(runtime).await?,
            Stage::Questionnaires => self.read_forms(runtime).await?,
            Stage::Courses => self.read_courses(runtime).await?,
        }
        Ok(())
    }
    async fn fetch(
        &mut self,
        runtime: &mut ClientRuntime,
        url: url::Url,
        complete: &mut bool,
    ) -> Result<Value> {
        match read::fetch_result(runtime, url, true).await {
            Ok(value) => Ok(value),
            Err(error) if !is_authentication_error(&error) => {
                *complete = false;
                self.error.get_or_insert(error);
                Ok(Value::Array(Vec::new()))
            }
            Err(error) => Err(error),
        }
    }
    async fn read_tasks(&mut self, runtime: &mut ClientRuntime) -> Result<()> {
        let url = read::tasks_url(runtime)?;
        let mut complete = true;
        let data = self.fetch(runtime, url, &mut complete).await?;
        let rows = read::rows_from_page_or_array(&data, "评教任务列表结构无效", false)?;
        complete &=
            (data.is_array() || data.get("list").is_some_and(Value::is_array)) && rows.len() < 10;
        for row in rows {
            if let Some(id) = row
                .as_object()
                .and_then(|row| canonical_string(row, "rwid"))
            {
                self.tasks.push(id);
            } else {
                complete = false;
            }
        }
        self.incomplete |= !complete;
        if self.tasks.is_empty() {
            self.finish();
        } else {
            self.stage = Stage::Questionnaires;
        }
        Ok(())
    }
    async fn read_forms(&mut self, runtime: &mut ClientRuntime) -> Result<()> {
        let rwid = self.tasks[self.task_index].clone();
        let url = read::questionnaires_url(runtime, &rwid)?;
        let mut complete = true;
        let data = self.fetch(runtime, url, &mut complete).await?;
        complete &= data.is_array();
        for row in read::rows_from_array(&data, "评教问卷列表结构无效", false)? {
            if let Some(row) = row.as_object()
                && let Some(wjid) = canonical_string(row, "wjid")
            {
                self.forms.push(read::course_context(row, &rwid, wjid));
            } else {
                complete = false;
            }
        }
        self.incomplete |= !complete;
        if self.forms.is_empty() {
            self.next_task();
        } else {
            self.stage = Stage::Courses;
        }
        Ok(())
    }
    async fn read_courses(&mut self, runtime: &mut ClientRuntime) -> Result<()> {
        let context = self.forms[self.form_index].clone();
        let url = read::courses_url(runtime, &context.wjid)?;
        let mut complete = true;
        let data = self.fetch(runtime, url, &mut complete).await?;
        complete &= read::course_rows_complete(&data, &context);
        match parse_course_rows(&data, &context) {
            Ok(entries) => self.entries.extend(entries.into_iter().map(|mut entry| {
                // 只留公开投影及重复目标判定；写前必须另行读取完整新鲜 authority。
                entry.authority = None;
                entry
            })),
            Err(error) if !is_authentication_error(&error) => complete = false,
            Err(error) => return Err(error),
        }
        self.incomplete |= !complete;
        self.completed_course_lists = self.completed_course_lists.saturating_add(1);
        self.form_index += 1;
        if self.form_index >= self.forms.len() {
            self.next_task();
        }
        Ok(())
    }
}
