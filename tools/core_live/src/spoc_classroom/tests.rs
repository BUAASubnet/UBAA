use std::future::{Future, ready};

use super::media::Probe;
use super::*;
use ubaa_core::facade::{ClassQuestion, TranscriptSegment};

const REPLAY_URL: &str = "https://fixture.invalid/sample-teacher.mp4";
const LIVE_URL: &str = "https://fixture.invalid/sample-live.m3u8?auth_key=fixture-secret";
const GUID: &str = "FixtureTeacherGuid";

#[derive(Default)]
struct Fixture {
    courses: usize,
    periods: bool,
    duplicate_mapping: bool,
    course_error: bool,
    catalog_calls: Vec<String>,
    session_calls: Vec<(String, String)>,
    material_calls: Vec<&'static str>,
    probe_calls: usize,
}

fn period(sub_id: &str, start_secs: i64, status: ClassroomStatus) -> ClassroomPeriod {
    ClassroomPeriod {
        sub_id: sub_id.into(),
        start_secs,
        status,
        title: "夹具节次".into(),
        week: None,
        end_secs: start_secs + 1,
        room: "夹具教室".into(),
        lecturer: "夹具姓名".into(),
        tencent_meeting: false,
    }
}

fn source(
    kind: PlaybackKind,
    url: &str,
    offset: Option<i64>,
    guid: Option<&str>,
) -> PlaybackSource {
    PlaybackSource {
        kind,
        url: url.into(),
        duration_secs: None,
        time_offset_secs: offset,
        resource_guid: guid.map(str::to_owned),
    }
}

impl ClassroomReads for Fixture {
    fn courses(&mut self) -> impl Future<Output = ReadResult<Vec<SpocCourse>>> {
        if self.course_error {
            return ready(Err(ErrorCode::NetworkError));
        }
        ready(Ok((1..=self.courses)
            .map(|index| SpocCourse {
                course_id: format!("fixture-kcid-{index}"),
                name: if index <= 2 {
                    "夹具同名课".into()
                } else {
                    format!("夹具课程{index}")
                },
                teacher: Some("夹具学号102938".into()),
                course_code: None,
            })
            .collect()))
    }

    fn catalog(
        &mut self,
        kcid: &str,
    ) -> impl Future<Output = Result<ClassroomCatalog, CatalogFailure>> {
        self.catalog_calls.push(kcid.into());
        let index = self.catalog_calls.len();
        if index > 2 {
            let (code, reason) = if index.is_multiple_of(2) {
                (
                    ErrorCode::Unsupported,
                    "spoc_mapping.role_teacher_unsupported",
                )
            } else {
                (
                    ErrorCode::BusinessUnavailable,
                    "spoc_mapping.bind_id_missing",
                )
            };
            return ready(Err(CatalogFailure {
                code,
                reason: Some(reason.into()),
            }));
        }
        let mut sessions = Vec::new();
        if self.periods && index == 1 {
            sessions.extend([
                period("fixture-replay-old", 10, ClassroomStatus::Replay),
                period("fixture-live", 30, ClassroomStatus::Live),
                period("fixture-no-replay", 31, ClassroomStatus::NoReplay),
                period("fixture-upcoming", 32, ClassroomStatus::Upcoming),
                ClassroomPeriod {
                    tencent_meeting: true,
                    ..period("fixture-meeting", 40, ClassroomStatus::Live)
                },
            ]);
            sessions.extend(
                [
                    ("R9", "invalid"),
                    ("R9", "12"),
                    ("invalid", "-12"),
                    ("R9", "12"),
                ]
                .into_iter()
                .map(|(sub_status, playback_status)| {
                    period(
                        "fixture-other",
                        33,
                        ClassroomStatus::Other {
                            sub_status: sub_status.into(),
                            playback_status: playback_status.into(),
                        },
                    )
                }),
            );
        } else if self.periods {
            sessions.push(period("fixture-replay-new", 20, ClassroomStatus::Replay));
        }
        ready(Ok(ClassroomCatalog {
            course_id: format!(
                "fixture-mapped-{}",
                if self.duplicate_mapping { 1 } else { index }
            ),
            title: "夹具课堂".into(),
            teachers: vec!["夹具姓名".into()],
            term_name: "夹具学期".into(),
            sessions,
        }))
    }

    fn session(
        &mut self,
        course: &str,
        sub: &str,
    ) -> impl Future<Output = ReadResult<ClassroomSession>> {
        self.session_calls.push((course.into(), sub.into()));
        let (status, sources) = match sub {
            "fixture-replay-new" => (
                ClassroomStatus::Replay,
                vec![
                    source(
                        PlaybackKind::Slides,
                        "https://fixture.invalid/slides.mp4",
                        Some(-120),
                        Some("FixtureSlidesGuid"),
                    ),
                    source(PlaybackKind::Teacher, REPLAY_URL, Some(0), Some(GUID)),
                ],
            ),
            "fixture-live" => (
                ClassroomStatus::Live,
                vec![source(PlaybackKind::Student, LIVE_URL, None, None)],
            ),
            _ => panic!("选取了错误的夹具节次"),
        };
        ready(Ok(ClassroomSession {
            title: "夹具节次".into(),
            start_secs: 20,
            end_secs: 21,
            status,
            sources,
        }))
    }

    fn transcript(
        &mut self,
        sub: &str,
        guid: &str,
    ) -> impl Future<Output = ReadResult<Transcript>> {
        assert_eq!((sub, guid), ("fixture-replay-new", GUID));
        self.material_calls.push("transcript");
        ready(Ok(Transcript {
            segments: vec![TranscriptSegment {
                begin_ms: 0,
                end_ms: 1,
                text: "夹具转写".into(),
            }],
        }))
    }

    fn summary(&mut self, sub: &str, guid: &str) -> impl Future<Output = ReadResult<ClassSummary>> {
        assert_eq!((sub, guid), ("fixture-replay-new", GUID));
        self.material_calls.push("summary");
        ready(Ok(ClassSummary {
            summary: Some("夹具摘要".into()),
            keywords: vec!["夹具关键词".into()],
            qa: vec![ClassQuestion {
                question: "夹具问题".into(),
                answer: "夹具答案".into(),
                start_ms: 0,
            }],
            ..ClassSummary::default()
        }))
    }

    fn slides(
        &mut self,
        course: &str,
        sub: &str,
        guid: &str,
    ) -> impl Future<Output = ReadResult<SlideTimeline>> {
        assert_eq!(
            (course, sub, guid),
            ("fixture-mapped-2", "fixture-replay-new", GUID)
        );
        self.material_calls.push("slides");
        ready(Ok(SlideTimeline { slides: vec![] }))
    }

    fn probe(
        &mut self,
        replay: Option<&str>,
        live: Option<&str>,
    ) -> impl Future<Output = MediaReport> {
        assert_eq!((replay, live), (Some(REPLAY_URL), Some(LIVE_URL)));
        self.probe_calls += 1;
        ready(MediaReport {
            proxy_env: true,
            replay: Some(Probe::Http {
                status: 206,
                matches: true,
            }),
            live: Some(Probe::RequestError("network_error")),
        })
    }
}

#[tokio::test]
async fn 课堂证据只含聚合字段且媒体错误不影响结论() {
    let mut fixture = Fixture {
        courses: 13,
        periods: true,
        ..Fixture::default()
    };
    let mut evidence = Evidence::capturing("webvpn");
    run(&mut fixture, &mut evidence).await;
    assert!(!evidence.failed());
    assert_eq!(fixture.catalog_calls.len(), 12);
    assert_eq!(
        fixture.session_calls,
        [
            ("fixture-mapped-2".into(), "fixture-replay-new".into()),
            ("fixture-mapped-1".into(), "fixture-live".into()),
        ]
    );
    assert_eq!(fixture.material_calls, ["transcript", "summary", "slides"]);
    assert_eq!(fixture.probe_calls, 1);
    let lines = evidence.captured();
    assert_eq!(lines.len(), 8);
    for (line, expected) in lines.iter().zip([
        "operation=courses status=PASS count=13",
        "operation=catalog status=PASS count=2 attempted_count=12 session_count=10 live_count=1 replay_count=2 no_replay_count=1 upcoming_count=1 tencent_meeting_count=1 other_count=4 duplicate_name_groups=1 distinct_mapping_matches=true error_counts=business_unavailable:5,unsupported:5 error_reasons=spoc_mapping.bind_id_missing:5,spoc_mapping.role_teacher_unsupported:5 other_status_values=R9/12:2,R9/invalid:1,invalid/-12:1",
        "operation=replay_session status=PASS count=2 has_teacher=true has_slides=true has_nonzero_offset=true",
        "operation=transcript status=PASS count=1",
        "operation=summary status=PASS has_summary=true keyword_count=1 qa_count=1 chapter_count=0",
        "operation=slides status=PASS count=0",
        "operation=live_session status=PASS has_teacher=false has_student=true",
        "operation=media_probe status=PASS http_proxy_env=true replay_http_status=206 replay_is_partial=true live_probe_error=network_error",
    ]) {
        let actual = line.split_whitespace().skip(3).filter(|field| !field.starts_with("elapsed_ms=")).collect::<Vec<_>>().join(" ");
        assert_eq!(actual, expected);
    }
    let output = lines.join("\n");
    for value in [
        "夹具",
        "102938",
        "fixture-",
        "https://",
        "auth_key",
        GUID,
        "FixtureSlidesGuid",
    ] {
        assert!(!output.contains(value));
    }
}

#[tokio::test]
async fn 空目录保留成功映射并标记缺少直播与回放() {
    let mut fixture = Fixture {
        courses: 2,
        duplicate_mapping: true,
        ..Fixture::default()
    };
    let mut evidence = Evidence::capturing("direct");
    run(&mut fixture, &mut evidence).await;
    assert!(!evidence.failed());
    let lines = evidence.captured();
    assert_eq!(lines.len(), 8);
    assert!(lines[1].contains("count=2 attempted_count=2 session_count=0"));
    assert!(lines[1].contains("duplicate_name_groups=1 distinct_mapping_matches=false"));
    assert!(lines[1].ends_with("error_reasons=none other_status_values=none"));
    for line in &lines[2..=5] {
        assert!(
            line.contains("status=NOT_APPLICABLE") && line.ends_with("reason=no_replay_session")
        );
    }
    assert!(lines[6].ends_with("reason=no_live_session"));
    assert!(lines[7].ends_with("reason=no_media_source"));
    assert_eq!(fixture.session_calls.len(), 0);
    assert_eq!(fixture.probe_calls, 0);
}

#[tokio::test]
async fn 没有课程和课程请求失败分别跳过与阻塞() {
    for course_error in [false, true] {
        let mut fixture = Fixture {
            course_error,
            ..Fixture::default()
        };
        let mut evidence = Evidence::capturing("direct");
        run(&mut fixture, &mut evidence).await;
        assert_eq!(evidence.failed(), course_error);
        let lines = evidence.captured();
        assert_eq!(lines.len(), 8);
        let status = if course_error {
            "status=BLOCKED"
        } else {
            "status=NOT_APPLICABLE"
        };
        assert!(lines[1..].iter().all(|line| line.contains(status)));
        assert_eq!(fixture.catalog_calls.len(), 0);
    }
}
