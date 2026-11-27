use super::spoc_classroom::*;
use crate::api::client::{BridgeConnectionMode, BridgeError, BridgeErrorCode};
use ubaa_core::facade::{self as core, ErrorCode, ErrorKind, UbaaError};

#[test]
fn classroom_catalog_preserves_periods_and_meeting_status() {
    let states = [
        (
            core::ClassroomStatus::Live,
            false,
            BridgeClassroomStatus::Live,
        ),
        (
            core::ClassroomStatus::Replay,
            false,
            BridgeClassroomStatus::Replay,
        ),
        (
            core::ClassroomStatus::NoReplay,
            false,
            BridgeClassroomStatus::NoReplay,
        ),
        (
            core::ClassroomStatus::Upcoming,
            false,
            BridgeClassroomStatus::Upcoming,
        ),
        (
            core::ClassroomStatus::Live,
            true,
            BridgeClassroomStatus::TencentMeeting,
        ),
        (
            core::ClassroomStatus::Other {
                sub_status: "3".into(),
                playback_status: "0".into(),
            },
            false,
            BridgeClassroomStatus::Other,
        ),
    ];
    let expected: Vec<_> = states.iter().map(|(_, _, expected)| *expected).collect();
    let catalog = BridgeClassroomCatalog::from(core::ClassroomCatalog {
        course_id: "101".into(),
        title: "合成课堂".into(),
        teachers: vec!["合成教师".into()],
        term_name: "合成学期".into(),
        sessions: states
            .into_iter()
            .map(|(status, tencent_meeting, _)| core::ClassroomPeriod {
                sub_id: "102".into(),
                title: "合成节次".into(),
                week: Some(3),
                start_secs: 10,
                end_secs: 20,
                room: "合成教室".into(),
                lecturer: "合成讲师".into(),
                status,
                tencent_meeting,
            })
            .collect(),
    });
    assert_eq!(catalog.course_id, "101");
    assert_eq!(catalog.title, "合成课堂");
    assert_eq!(catalog.teachers, ["合成教师"]);
    assert_eq!(catalog.term_name, "合成学期");
    assert_eq!(
        catalog
            .sessions
            .iter()
            .map(|period| period.status)
            .collect::<Vec<_>>(),
        expected
    );
    let period = &catalog.sessions[0];
    assert_eq!(period.sub_id, "102");
    assert_eq!(period.title, "合成节次");
    assert_eq!(period.week, Some(3));
    assert_eq!((period.start_secs, period.end_secs), (10, 20));
    assert_eq!((&*period.room, &*period.lecturer), ("合成教室", "合成讲师"));
}

#[test]
fn classroom_session_and_materials_keep_source_and_timeline_fields() {
    let url = "https://example.invalid/fixture.mp4";
    let session = BridgeClassroomSession::from(core::ClassroomSession {
        title: "合成回放".into(),
        start_secs: 10,
        end_secs: 20,
        status: core::ClassroomStatus::Replay,
        sources: vec![core::PlaybackSource {
            kind: core::PlaybackKind::Slides,
            url: url.into(),
            duration_secs: Some(60),
            time_offset_secs: Some(-12),
            resource_guid: Some("fixture123".into()),
        }],
    });
    assert_eq!(session.status, BridgeClassroomStatus::Replay);
    assert_eq!(
        (&*session.title, session.start_secs, session.end_secs),
        ("合成回放", 10, 20)
    );
    let source = &session.sources[0];
    assert_eq!(source.kind, BridgeClassroomPlaybackKind::Slides);
    assert_eq!(source.url, url);
    assert_eq!(source.duration_secs, Some(60));
    assert_eq!(source.time_offset_secs, Some(-12));
    assert_eq!(source.resource_guid.as_deref(), Some("fixture123"));
    assert_eq!(
        BridgeClassroomPlaybackKind::from(core::PlaybackKind::Teacher),
        BridgeClassroomPlaybackKind::Teacher
    );
    assert_eq!(
        BridgeClassroomPlaybackKind::from(core::PlaybackKind::Student),
        BridgeClassroomPlaybackKind::Student
    );

    let transcript = BridgeClassroomTranscript::from(core::Transcript {
        segments: vec![core::TranscriptSegment {
            begin_ms: 125,
            end_ms: 200,
            text: "合成转写".into(),
        }],
    });
    let segment = &transcript.segments[0];
    assert_eq!(
        (segment.begin_ms, segment.end_ms, &*segment.text),
        (125, 200, "合成转写")
    );

    let summary = BridgeClassroomSummary::from(core::ClassSummary {
        summary: Some("合成摘要".into()),
        keywords: vec!["关键词".into()],
        qa: vec![core::ClassQuestion {
            question: "提问".into(),
            answer: "回答".into(),
            start_ms: 100,
        }],
        chapters: vec![core::ClassChapter {
            start_ms: 200,
            end_ms: 500,
            headline: "章节".into(),
            summary: "简介".into(),
        }],
    });
    assert_eq!(summary.summary.as_deref(), Some("合成摘要"));
    assert_eq!(summary.keywords, ["关键词"]);
    let qa = &summary.qa[0];
    assert_eq!(
        (&*qa.question, &*qa.answer, qa.start_ms),
        ("提问", "回答", 100)
    );
    let chapter = &summary.chapters[0];
    assert_eq!(
        (
            chapter.start_ms,
            chapter.end_ms,
            &*chapter.headline,
            &*chapter.summary
        ),
        (200, 500, "章节", "简介")
    );

    let slides = BridgeClassroomSlides::from(core::SlideTimeline {
        slides: vec![core::ClassSlide {
            offset_ms: 500,
            image_url: "https://example.invalid/slide.png".into(),
            thumb_url: "https://example.invalid/thumb.png".into(),
        }],
    });
    let slide = &slides.slides[0];
    assert_eq!(
        (slide.offset_ms, &*slide.image_url, &*slide.thumb_url),
        (
            500,
            "https://example.invalid/slide.png",
            "https://example.invalid/thumb.png"
        )
    );
}

#[test]
fn classroom_errors_preserve_codes_and_resolved_route() {
    use ubaa_core::facade::{
        ConnectionMode, NetworkState, RouteDiagnostic, RoutePolicy, RouteResolution,
    };

    let mode = ConnectionMode::WebVpn;
    for (error, expected, retryable) in [
        (
            UbaaError::new(
                ErrorCode::Unsupported,
                ErrorKind::Upstream,
                false,
                "暂不支持教师身份",
            ),
            BridgeErrorCode::Unsupported,
            false,
        ),
        (
            UbaaError::business_unavailable("该课程未开通课堂直录播"),
            BridgeErrorCode::BusinessUnavailable,
            true,
        ),
    ] {
        let projected = BridgeError::from_routed(core::RoutedError {
            error,
            resolution: Some(RouteResolution {
                mode,
                policy: RoutePolicy::WebVpn,
                diagnostic: RouteDiagnostic::new(NetworkState::OffCampus, mode),
            }),
        });
        assert_eq!(projected.code, expected);
        assert_eq!(projected.retryable, retryable);
        assert!(matches!(
            projected.resolved_route,
            Some(BridgeConnectionMode::WebVpn)
        ));
    }
}
