//! 成绩变化比较只需的派生值，与学校写入及认证完全无关。
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedGradeScoreEntry {
    pub key: String,
    pub course_name: Option<String>,
    pub course_code: Option<String>,
    pub score: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct CachedGradeScoreBaseline {
    pub term_code: String,
    pub term_name: String,
    pub scores: Vec<CachedGradeScoreEntry>,
}

impl CachedGradeScoreBaseline {
    pub(crate) fn valid(&self) -> bool {
        crate::features::grades::parse_term_code(&self.term_code).is_ok()
            && self.term_name.len() <= 1024
            && !self.scores.is_empty()
            && self.scores.len() <= 4096
            && self.scores.iter().all(|entry| {
                let bounded =
                    |value: &Option<String>| value.as_ref().is_none_or(|value| value.len() <= 4096);
                !entry.key.trim().is_empty()
                    && entry.key.len() <= 8192
                    && bounded(&entry.course_name)
                    && bounded(&entry.course_code)
                    && bounded(&entry.score)
            })
    }
}
