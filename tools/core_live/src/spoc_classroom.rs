//! SPOC 课堂真实只读验证与聚合证据。

use std::collections::{BTreeMap, HashMap, HashSet};

use ubaa_core::facade::{
    ClassSummary, ClassroomCatalog, ClassroomPeriod, ClassroomSession, ClassroomStatus, ErrorCode,
    PlaybackKind, PlaybackSource, SlideTimeline, SpocCourse, Transcript, UbaaClient, UbaaError,
};

use crate::evidence::{Evidence, error_code};

mod media;
use media::MediaReport;
#[cfg(test)]
mod tests;

pub(crate) const FEATURE: &str = "spoc_classroom";
pub(crate) const OPERATIONS: &[&str] = &[
    "courses",
    "catalog",
    "replay_session",
    "transcript",
    "summary",
    "slides",
    "live_session",
    "media_probe",
];
const MATERIALS: &[&str] = &["transcript", "summary", "slides"];
const COURSE_LIMIT: usize = 12;

type ReadResult<T> = Result<T, ErrorCode>;

pub(crate) struct CatalogFailure {
    code: ErrorCode,
    reason: Option<String>,
}

impl From<UbaaError> for CatalogFailure {
    fn from(error: UbaaError) -> Self {
        let diagnostic = error.diagnostic();
        Self {
            code: error.code,
            reason: diagnostic
                .stage
                .as_deref()
                .zip(diagnostic.reason.as_deref())
                .map(|(stage, reason)| format!("{stage}.{reason}")),
        }
    }
}

pub(crate) trait ClassroomReads {
    async fn courses(&mut self) -> ReadResult<Vec<SpocCourse>>;
    async fn catalog(&mut self, kcid: &str) -> Result<ClassroomCatalog, CatalogFailure>;
    async fn session(&mut self, course: &str, sub: &str) -> ReadResult<ClassroomSession>;
    async fn transcript(&mut self, sub: &str, guid: &str) -> ReadResult<Transcript>;
    async fn summary(&mut self, sub: &str, guid: &str) -> ReadResult<ClassSummary>;
    async fn slides(&mut self, course: &str, sub: &str, guid: &str) -> ReadResult<SlideTimeline>;
    async fn probe(&mut self, replay: Option<&str>, live: Option<&str>) -> MediaReport;
}

impl ClassroomReads for UbaaClient {
    async fn courses(&mut self) -> ReadResult<Vec<SpocCourse>> {
        self.spoc_courses()
            .await
            .map(|result| result.data)
            .map_err(|error| error.error.code)
    }

    async fn catalog(&mut self, kcid: &str) -> Result<ClassroomCatalog, CatalogFailure> {
        self.spoc_classroom_catalog(kcid)
            .await
            .map(|result| result.data)
            .map_err(|error| error.error.into())
    }

    async fn session(&mut self, course: &str, sub: &str) -> ReadResult<ClassroomSession> {
        self.spoc_classroom_session(course, sub)
            .await
            .map(|result| result.data)
            .map_err(|error| error.error.code)
    }

    async fn transcript(&mut self, sub: &str, guid: &str) -> ReadResult<Transcript> {
        self.spoc_classroom_transcript(sub, guid)
            .await
            .map(|result| result.data)
            .map_err(|error| error.error.code)
    }

    async fn summary(&mut self, sub: &str, guid: &str) -> ReadResult<ClassSummary> {
        self.spoc_classroom_summary(sub, guid)
            .await
            .map(|result| result.data)
            .map_err(|error| error.error.code)
    }

    async fn slides(&mut self, course: &str, sub: &str, guid: &str) -> ReadResult<SlideTimeline> {
        self.spoc_classroom_slides(course, sub, guid)
            .await
            .map(|result| result.data)
            .map_err(|error| error.error.code)
    }

    async fn probe(&mut self, replay: Option<&str>, live: Option<&str>) -> MediaReport {
        media::probe(replay, live).await
    }
}

pub(crate) async fn run(client: &mut impl ClassroomReads, evidence: &mut Evidence) {
    let courses = match client.courses().await {
        Ok(courses) => {
            evidence.pass(FEATURE, "courses", Some(courses.len()));
            courses
        }
        Err(code) => {
            evidence.fail(FEATURE, "courses", code);
            for operation in &OPERATIONS[1..] {
                evidence.blocked(FEATURE, operation, "courses_failed");
            }
            return;
        }
    };
    if courses.is_empty() {
        skip(evidence, &OPERATIONS[1..], "no_courses");
        return;
    }
    let catalogs = catalogs(client, evidence, &courses).await;
    if catalogs.is_empty() {
        for operation in &OPERATIONS[2..] {
            evidence.blocked(FEATURE, operation, "catalog_failed");
        }
        return;
    }

    let replay = replay_session(
        client,
        evidence,
        latest(&catalogs, &ClassroomStatus::Replay),
    )
    .await;
    let live = live_session(client, evidence, latest(&catalogs, &ClassroomStatus::Live)).await;
    let replay = replay.as_ref().and_then(|session| {
        session
            .sources
            .iter()
            .find(|source| source.kind == PlaybackKind::Teacher && media::is_mp4(&source.url))
    });
    let live = live
        .as_ref()
        .filter(|session| session.status == ClassroomStatus::Live)
        .and_then(|session| {
            source(session, PlaybackKind::Teacher)
                .or_else(|| source(session, PlaybackKind::Student))
        });
    if replay.is_none() && live.is_none() {
        evidence.not_applicable(FEATURE, "media_probe", "no_media_source");
    } else {
        let media = client
            .probe(
                replay.map(|source| source.url.as_str()),
                live.map(|source| source.url.as_str()),
            )
            .await;
        evidence.pass_with_fields(FEATURE, "media_probe", None, &media.fields());
    }
}

async fn catalogs(
    client: &mut impl ClassroomReads,
    evidence: &mut Evidence,
    courses: &[SpocCourse],
) -> Vec<ClassroomCatalog> {
    let courses = &courses[..courses.len().min(COURSE_LIMIT)];
    let mut catalogs = Vec::new();
    let mut errors = BTreeMap::new();
    let mut reasons = BTreeMap::new();
    let mut other_statuses = BTreeMap::new();
    let mut groups = HashMap::<&str, (HashSet<&str>, HashSet<String>)>::new();
    let mut sessions = [0usize; 6];
    for course in courses {
        let (kcids, mapped) = groups.entry(&course.name).or_default();
        kcids.insert(&course.course_id);
        match client.catalog(&course.course_id).await {
            Ok(catalog) => {
                mapped.insert(catalog.course_id.clone());
                for period in &catalog.sessions {
                    let index = if period.tencent_meeting {
                        4
                    } else {
                        match &period.status {
                            ClassroomStatus::Live => 0,
                            ClassroomStatus::Replay => 1,
                            ClassroomStatus::NoReplay => 2,
                            ClassroomStatus::Upcoming => 3,
                            ClassroomStatus::Other {
                                sub_status,
                                playback_status,
                            } => {
                                *other_statuses
                                    .entry(format!("{sub_status}/{playback_status}"))
                                    .or_insert(0) += 1;
                                5
                            }
                        }
                    };
                    sessions[index] += 1;
                }
                catalogs.push(catalog);
            }
            Err(error) => {
                *errors.entry(error_code(error.code)).or_insert(0) += 1;
                if let Some(reason) = error.reason {
                    *reasons.entry(reason).or_insert(0) += 1;
                }
            }
        }
    }
    let mut duplicate_groups = groups.values().filter(|(kcids, _)| kcids.len() > 1);
    let group_count = duplicate_groups.clone().count();
    let mapping_matches = duplicate_groups.all(|(kcids, mapped)| kcids.len() == mapped.len());
    let fields = [
        ("attempted_count", courses.len().to_string()),
        ("session_count", sessions.iter().sum::<usize>().to_string()),
        ("live_count", sessions[0].to_string()),
        ("replay_count", sessions[1].to_string()),
        ("no_replay_count", sessions[2].to_string()),
        ("upcoming_count", sessions[3].to_string()),
        ("tencent_meeting_count", sessions[4].to_string()),
        ("other_count", sessions[5].to_string()),
        ("duplicate_name_groups", group_count.to_string()),
        ("distinct_mapping_matches", mapping_matches.to_string()),
        ("error_counts", format_counts(errors)),
        ("error_reasons", format_counts(reasons)),
        ("other_status_values", format_counts(other_statuses)),
    ];
    if catalogs.is_empty() {
        evidence.fail_with_fields(FEATURE, "catalog", "no_catalog_mapping", Some(0), &fields);
    } else {
        evidence.pass_with_fields(FEATURE, "catalog", Some(catalogs.len()), &fields);
    }
    catalogs
}

fn format_counts(counts: BTreeMap<impl std::fmt::Display, usize>) -> String {
    if counts.is_empty() {
        "none".into()
    } else {
        counts
            .into_iter()
            .map(|(key, count)| format!("{key}:{count}"))
            .collect::<Vec<_>>()
            .join(",")
    }
}

fn latest<'catalogs>(
    catalogs: &'catalogs [ClassroomCatalog],
    status: &ClassroomStatus,
) -> Option<(&'catalogs str, &'catalogs ClassroomPeriod)> {
    catalogs
        .iter()
        .flat_map(|catalog| {
            catalog
                .sessions
                .iter()
                .map(|period| (catalog.course_id.as_str(), period))
        })
        .filter(|(_, period)| !period.tencent_meeting && &period.status == status)
        .max_by_key(|(_, period)| period.start_secs)
}

fn source(session: &ClassroomSession, kind: PlaybackKind) -> Option<&PlaybackSource> {
    session.sources.iter().find(|source| source.kind == kind)
}

fn skip(evidence: &Evidence, operations: &[&str], reason: &str) {
    for operation in operations {
        evidence.not_applicable(FEATURE, operation, reason);
    }
}

async fn replay_session(
    client: &mut impl ClassroomReads,
    evidence: &mut Evidence,
    selected: Option<(&str, &ClassroomPeriod)>,
) -> Option<ClassroomSession> {
    let Some((course, period)) = selected else {
        evidence.not_applicable(FEATURE, "replay_session", "no_replay_session");
        skip(evidence, MATERIALS, "no_replay_session");
        return None;
    };
    let session = match client.session(course, &period.sub_id).await {
        Ok(session) => session,
        Err(code) => {
            evidence.fail(FEATURE, "replay_session", code);
            for operation in MATERIALS {
                evidence.blocked(FEATURE, operation, "replay_session_failed");
            }
            return None;
        }
    };
    let has_teacher = source(&session, PlaybackKind::Teacher).is_some();
    let has_slides = source(&session, PlaybackKind::Slides).is_some();
    let has_nonzero_offset = session
        .sources
        .iter()
        .any(|source| source.time_offset_secs.is_some_and(|offset| offset != 0));
    evidence.pass_with_fields(
        FEATURE,
        "replay_session",
        Some(session.sources.len()),
        &[
            ("has_teacher", has_teacher.to_string()),
            ("has_slides", has_slides.to_string()),
            ("has_nonzero_offset", has_nonzero_offset.to_string()),
        ],
    );
    if let Some(guid) = session
        .sources
        .iter()
        .filter(|source| source.kind == PlaybackKind::Teacher)
        .find_map(|source| source.resource_guid.as_deref())
    {
        materials(client, evidence, course, &period.sub_id, guid).await;
    } else {
        skip(evidence, MATERIALS, "no_teacher_guid");
    }
    Some(session)
}

async fn materials(
    client: &mut impl ClassroomReads,
    evidence: &mut Evidence,
    course: &str,
    sub: &str,
    guid: &str,
) {
    match client.transcript(sub, guid).await {
        Ok(transcript) => evidence.pass(FEATURE, "transcript", Some(transcript.segments.len())),
        Err(code) => evidence.fail(FEATURE, "transcript", code),
    }
    match client.summary(sub, guid).await {
        Ok(summary) => evidence.pass_with_fields(
            FEATURE,
            "summary",
            None,
            &[
                (
                    "has_summary",
                    summary
                        .summary
                        .is_some_and(|text| !text.trim().is_empty())
                        .to_string(),
                ),
                ("keyword_count", summary.keywords.len().to_string()),
                ("qa_count", summary.qa.len().to_string()),
                ("chapter_count", summary.chapters.len().to_string()),
            ],
        ),
        Err(code) => evidence.fail(FEATURE, "summary", code),
    }
    match client.slides(course, sub, guid).await {
        Ok(timeline) => evidence.pass(FEATURE, "slides", Some(timeline.slides.len())),
        Err(code) => evidence.fail(FEATURE, "slides", code),
    }
}

async fn live_session(
    client: &mut impl ClassroomReads,
    evidence: &mut Evidence,
    selected: Option<(&str, &ClassroomPeriod)>,
) -> Option<ClassroomSession> {
    let Some((course, period)) = selected else {
        evidence.not_applicable(FEATURE, "live_session", "no_live_session");
        return None;
    };
    match client.session(course, &period.sub_id).await {
        Ok(session) => {
            evidence.pass_with_fields(
                FEATURE,
                "live_session",
                None,
                &[
                    (
                        "has_teacher",
                        source(&session, PlaybackKind::Teacher)
                            .is_some()
                            .to_string(),
                    ),
                    (
                        "has_student",
                        source(&session, PlaybackKind::Student)
                            .is_some()
                            .to_string(),
                    ),
                ],
            );
            Some(session)
        }
        Err(code) => {
            evidence.fail(FEATURE, "live_session", code);
            None
        }
    }
}
