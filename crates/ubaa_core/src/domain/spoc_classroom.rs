#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ClassroomStatus {
    Live,
    Replay,
    NoReplay,
    Upcoming,
    Other(String),
}

#[derive(Debug)]
pub struct ClassroomCatalog {
    pub course_id: String,
    pub title: String,
    pub teachers: Vec<String>,
    pub term_name: String,
    pub sessions: Vec<ClassroomPeriod>,
}
#[derive(Debug)]
pub struct ClassroomPeriod {
    pub sub_id: String,
    pub title: String,
    pub week: Option<u32>,
    pub start_secs: i64,
    pub end_secs: i64,
    pub room: String,
    pub lecturer: String,
    pub status: ClassroomStatus,
    pub tencent_meeting: bool,
}
#[derive(Debug)]
pub struct ClassroomSession {
    pub title: String,
    pub start_secs: i64,
    pub end_secs: i64,
    pub status: ClassroomStatus,
    pub sources: Vec<PlaybackSource>,
}
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum PlaybackKind {
    Teacher,
    Slides,
    Student,
}
pub struct PlaybackSource {
    pub kind: PlaybackKind,
    pub url: String,
    pub duration_secs: Option<u64>,
    pub time_offset_secs: Option<i64>,
    pub resource_guid: Option<String>,
}
impl std::fmt::Debug for PlaybackSource {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("PlaybackSource")
            .field("kind", &self.kind)
            .finish_non_exhaustive()
    }
}
#[derive(Debug)]
pub struct Transcript {
    pub segments: Vec<TranscriptSegment>,
}
#[derive(Debug)]
pub struct TranscriptSegment {
    pub begin_ms: u64,
    pub end_ms: u64,
    pub text: String,
}
#[derive(Debug, Default)]
pub struct ClassSummary {
    pub summary: Option<String>,
    pub keywords: Vec<String>,
    pub qa: Vec<ClassQuestion>,
    pub chapters: Vec<ClassChapter>,
}
#[derive(Debug, PartialEq, Eq, Hash, Clone)]
pub struct ClassQuestion {
    pub question: String,
    pub answer: String,
    pub start_ms: u64,
}
#[derive(Debug)]
pub struct ClassChapter {
    pub start_ms: u64,
    pub end_ms: u64,
    pub headline: String,
    pub summary: String,
}
#[derive(Debug)]
pub struct SlideTimeline {
    pub slides: Vec<ClassSlide>,
}
pub struct ClassSlide {
    pub offset_ms: u64,
    pub image_url: String,
    pub thumb_url: String,
}
impl std::fmt::Debug for ClassSlide {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ClassSlide")
            .field("offset_ms", &self.offset_ms)
            .finish_non_exhaustive()
    }
}
