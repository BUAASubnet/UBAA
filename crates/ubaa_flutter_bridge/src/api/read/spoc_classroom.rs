use crate::api::{
    client::{BridgeClient, BridgeError, BridgeRouteDecision},
    read_pool::ReadGroup,
};
use ubaa_core::facade as core;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeClassroomStatus {
    Live,
    Replay,
    NoReplay,
    Upcoming,
    TencentMeeting,
    Other,
}

impl From<core::ClassroomStatus> for BridgeClassroomStatus {
    fn from(value: core::ClassroomStatus) -> Self {
        match value {
            core::ClassroomStatus::Live => Self::Live,
            core::ClassroomStatus::Replay => Self::Replay,
            core::ClassroomStatus::NoReplay => Self::NoReplay,
            core::ClassroomStatus::Upcoming => Self::Upcoming,
            core::ClassroomStatus::Other { .. } => Self::Other,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BridgeClassroomPlaybackKind {
    Teacher,
    Slides,
    Student,
}

impl From<core::PlaybackKind> for BridgeClassroomPlaybackKind {
    fn from(value: core::PlaybackKind) -> Self {
        match value {
            core::PlaybackKind::Teacher => Self::Teacher,
            core::PlaybackKind::Slides => Self::Slides,
            core::PlaybackKind::Student => Self::Student,
        }
    }
}

pub struct BridgeClassroomCatalog {
    pub course_id: String,
    pub title: String,
    pub teachers: Vec<String>,
    pub term_name: String,
    pub sessions: Vec<BridgeClassroomSessionSummary>,
}

pub struct BridgeClassroomSessionSummary {
    pub sub_id: String,
    pub title: String,
    pub week: Option<u32>,
    pub start_secs: i64,
    pub end_secs: i64,
    pub room: String,
    pub lecturer: String,
    pub status: BridgeClassroomStatus,
}

pub struct BridgeClassroomSession {
    pub title: String,
    pub start_secs: i64,
    pub end_secs: i64,
    pub status: BridgeClassroomStatus,
    pub sources: Vec<BridgeClassroomPlaybackSource>,
}

pub struct BridgeClassroomPlaybackSource {
    pub kind: BridgeClassroomPlaybackKind,
    pub url: String,
    pub duration_secs: Option<u64>,
    pub time_offset_secs: Option<i64>,
    pub resource_guid: Option<String>,
}

pub struct BridgeClassroomTranscript {
    pub segments: Vec<BridgeClassroomTranscriptSegment>,
}

pub struct BridgeClassroomTranscriptSegment {
    pub begin_ms: u64,
    pub end_ms: u64,
    pub text: String,
}

pub struct BridgeClassroomSummary {
    pub summary: Option<String>,
    pub keywords: Vec<String>,
    pub qa: Vec<BridgeClassroomQuestion>,
    pub chapters: Vec<BridgeClassroomChapter>,
}

pub struct BridgeClassroomQuestion {
    pub question: String,
    pub answer: String,
    pub start_ms: u64,
}

pub struct BridgeClassroomChapter {
    pub start_ms: u64,
    pub end_ms: u64,
    pub headline: String,
    pub summary: String,
}

pub struct BridgeClassroomSlides {
    pub slides: Vec<BridgeClassroomSlide>,
}

pub struct BridgeClassroomSlide {
    pub offset_ms: u64,
    pub image_url: String,
    pub thumb_url: String,
}

pub struct BridgeRoutedClassroomCatalog {
    pub data: BridgeClassroomCatalog,
    pub route: BridgeRouteDecision,
}

pub struct BridgeRoutedClassroomSession {
    pub data: BridgeClassroomSession,
    pub route: BridgeRouteDecision,
}

pub struct BridgeRoutedClassroomTranscript {
    pub data: BridgeClassroomTranscript,
    pub route: BridgeRouteDecision,
}

pub struct BridgeRoutedClassroomSummary {
    pub data: BridgeClassroomSummary,
    pub route: BridgeRouteDecision,
}

pub struct BridgeRoutedClassroomSlides {
    pub data: BridgeClassroomSlides,
    pub route: BridgeRouteDecision,
}

impl From<core::ClassroomCatalog> for BridgeClassroomCatalog {
    fn from(value: core::ClassroomCatalog) -> Self {
        Self {
            course_id: value.course_id,
            title: value.title,
            teachers: value.teachers,
            term_name: value.term_name,
            sessions: value
                .sessions
                .into_iter()
                .map(|period| BridgeClassroomSessionSummary {
                    sub_id: period.sub_id,
                    title: period.title,
                    week: period.week,
                    start_secs: period.start_secs,
                    end_secs: period.end_secs,
                    room: period.room,
                    lecturer: period.lecturer,
                    status: if period.tencent_meeting {
                        BridgeClassroomStatus::TencentMeeting
                    } else {
                        period.status.into()
                    },
                })
                .collect(),
        }
    }
}

impl From<core::ClassroomSession> for BridgeClassroomSession {
    fn from(value: core::ClassroomSession) -> Self {
        Self {
            title: value.title,
            start_secs: value.start_secs,
            end_secs: value.end_secs,
            status: value.status.into(),
            sources: value
                .sources
                .into_iter()
                .map(|source| BridgeClassroomPlaybackSource {
                    kind: source.kind.into(),
                    url: source.url,
                    duration_secs: source.duration_secs,
                    time_offset_secs: source.time_offset_secs,
                    resource_guid: source.resource_guid,
                })
                .collect(),
        }
    }
}

impl From<core::Transcript> for BridgeClassroomTranscript {
    fn from(value: core::Transcript) -> Self {
        Self {
            segments: value
                .segments
                .into_iter()
                .map(|segment| BridgeClassroomTranscriptSegment {
                    begin_ms: segment.begin_ms,
                    end_ms: segment.end_ms,
                    text: segment.text,
                })
                .collect(),
        }
    }
}

impl From<core::ClassSummary> for BridgeClassroomSummary {
    fn from(value: core::ClassSummary) -> Self {
        Self {
            summary: value.summary,
            keywords: value.keywords,
            qa: value
                .qa
                .into_iter()
                .map(|item| BridgeClassroomQuestion {
                    question: item.question,
                    answer: item.answer,
                    start_ms: item.start_ms,
                })
                .collect(),
            chapters: value
                .chapters
                .into_iter()
                .map(|item| BridgeClassroomChapter {
                    start_ms: item.start_ms,
                    end_ms: item.end_ms,
                    headline: item.headline,
                    summary: item.summary,
                })
                .collect(),
        }
    }
}

impl From<core::SlideTimeline> for BridgeClassroomSlides {
    fn from(value: core::SlideTimeline) -> Self {
        Self {
            slides: value
                .slides
                .into_iter()
                .map(|slide| BridgeClassroomSlide {
                    offset_ms: slide.offset_ms,
                    image_url: slide.image_url,
                    thumb_url: slide.thumb_url,
                })
                .collect(),
        }
    }
}

impl BridgeClient {
    pub async fn spoc_classroom_catalog(
        &self,
        kcid: String,
    ) -> Result<BridgeRoutedClassroomCatalog, BridgeError> {
        let (data, route) = self
            .execute_read(
                Some(ReadGroup::Spoc),
                move |client| Box::pin(async move { client.spoc_classroom_catalog(&kcid).await }),
                BridgeClassroomCatalog::from,
            )
            .await?;
        Ok(BridgeRoutedClassroomCatalog { data, route })
    }

    pub async fn spoc_classroom_session(
        &self,
        course_id: String,
        sub_id: String,
    ) -> Result<BridgeRoutedClassroomSession, BridgeError> {
        let (data, route) = self
            .execute_read(
                Some(ReadGroup::Spoc),
                move |client| {
                    Box::pin(
                        async move { client.spoc_classroom_session(&course_id, &sub_id).await },
                    )
                },
                BridgeClassroomSession::from,
            )
            .await?;
        Ok(BridgeRoutedClassroomSession { data, route })
    }

    pub async fn spoc_classroom_transcript(
        &self,
        sub_id: String,
        resource_guid: String,
    ) -> Result<BridgeRoutedClassroomTranscript, BridgeError> {
        let (data, route) = self
            .execute_read(
                Some(ReadGroup::Spoc),
                move |client| {
                    Box::pin(async move {
                        client
                            .spoc_classroom_transcript(&sub_id, &resource_guid)
                            .await
                    })
                },
                BridgeClassroomTranscript::from,
            )
            .await?;
        Ok(BridgeRoutedClassroomTranscript { data, route })
    }

    pub async fn spoc_classroom_summary(
        &self,
        sub_id: String,
        resource_guid: String,
    ) -> Result<BridgeRoutedClassroomSummary, BridgeError> {
        let (data, route) = self
            .execute_read(
                Some(ReadGroup::Spoc),
                move |client| {
                    Box::pin(
                        async move { client.spoc_classroom_summary(&sub_id, &resource_guid).await },
                    )
                },
                BridgeClassroomSummary::from,
            )
            .await?;
        Ok(BridgeRoutedClassroomSummary { data, route })
    }

    pub async fn spoc_classroom_slides(
        &self,
        course_id: String,
        sub_id: String,
        resource_guid: String,
    ) -> Result<BridgeRoutedClassroomSlides, BridgeError> {
        let (data, route) = self
            .execute_read(
                Some(ReadGroup::Spoc),
                move |client| {
                    Box::pin(async move {
                        client
                            .spoc_classroom_slides(&course_id, &sub_id, &resource_guid)
                            .await
                    })
                },
                BridgeClassroomSlides::from,
            )
            .await?;
        Ok(BridgeRoutedClassroomSlides { data, route })
    }
}
