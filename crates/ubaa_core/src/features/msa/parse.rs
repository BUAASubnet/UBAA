use super::{changed, digits, guid, media_url};
use crate::domain::spoc_classroom::{
    ClassChapter, ClassQuestion, ClassSlide, ClassSummary, ClassroomCatalog, ClassroomPeriod,
    ClassroomSession, ClassroomStatus, PlaybackKind, PlaybackSource, SlideTimeline, Transcript,
    TranscriptSegment,
};
use crate::{domain::ConnectionMode, error::Result};
use serde_json::Value;
use std::collections::HashSet;

const STAGE: &str = "msa_parse";

fn text<'value>(value: &'value Value, reason: &'static str) -> Result<&'value str> {
    value.as_str().ok_or_else(|| changed(STAGE, reason))
}
fn string(value: &Value, reason: &'static str) -> Result<String> {
    Ok(text(value, reason)?.to_owned())
}
fn integer(value: &Value) -> Option<i64> {
    value.as_i64().or_else(|| value.as_str()?.parse().ok())
}
fn int(value: &Value, reason: &'static str) -> Result<i64> {
    integer(value).ok_or_else(|| changed(STAGE, reason))
}
fn unsigned(value: &Value, reason: &'static str) -> Result<u64> {
    integer(value)
        .and_then(|number| number.try_into().ok())
        .ok_or_else(|| changed(STAGE, reason))
}
fn array<'value>(value: &'value Value, reason: &'static str) -> Result<&'value Vec<Value>> {
    value.as_array().ok_or_else(|| changed(STAGE, reason))
}
fn object<'value>(
    value: &'value Value,
    reason: &'static str,
) -> Result<&'value serde_json::Map<String, Value>> {
    value.as_object().ok_or_else(|| changed(STAGE, reason))
}
fn status_value(value: &Value) -> String {
    match value {
        Value::Number(number) => number.to_string(),
        Value::String(text) => status_text(text).into(),
        _ => "invalid".into(),
    }
}
fn status_text(value: &str) -> &str {
    if (1..=8).contains(&value.len()) && value.bytes().all(|byte| byte.is_ascii_alphanumeric()) {
        value
    } else {
        "invalid"
    }
}
fn status(raw: &str, playback: &Value) -> ClassroomStatus {
    match (raw, playback.as_str()) {
        ("1", _) => ClassroomStatus::Live,
        ("2", _) => ClassroomStatus::Upcoming,
        ("6", Some("1")) => ClassroomStatus::Replay,
        ("6", Some("0")) => ClassroomStatus::NoReplay,
        _ => ClassroomStatus::Other {
            sub_status: status_text(raw).into(),
            playback_status: status_value(playback),
        },
    }
}
pub(super) fn catalog(data: &Value, course: &str) -> Result<ClassroomCatalog> {
    if !data.is_object() {
        return Err(changed(STAGE, "catalog_shape"));
    }
    if data["id"].as_str() != Some(course) {
        return Err(changed(STAGE, "catalog_course_id"));
    }
    let mut sessions = Vec::new();
    for months in object(&data["sub_list"], "sub_list_shape")?.values() {
        for days in object(months, "sub_list_year_shape")?.values() {
            for group in object(days, "sub_list_month_shape")?.values() {
                for item in array(group, "sub_list_day_shape")? {
                    let title = text(&item["sub_title"], "catalog_period_title")?;
                    let week = title
                        .strip_prefix('第')
                        .and_then(|tail| tail.split_once('周'))
                        .and_then(|(num, _)| digits(num).then(|| num.parse().ok()).flatten());
                    let sub = item["id"]
                        .as_str()
                        .filter(|value| digits(value))
                        .ok_or_else(|| changed(STAGE, "catalog_period_id"))?;
                    sessions.push(ClassroomPeriod {
                        sub_id: sub.into(),
                        title: title.into(),
                        week,
                        start_secs: int(&item["class_begin"], "catalog_period_start")?,
                        end_secs: int(&item["class_over"], "catalog_period_end")?,
                        room: string(&item["room_name"], "catalog_period_room")?,
                        lecturer: string(&item["lecturer_name"], "catalog_period_lecturer")?,
                        status: status(
                            text(&item["sub_status"], "catalog_period_status")?,
                            &item["playback_status"],
                        ),
                        tencent_meeting: item["olive_type"] == "tencent_meeting",
                    });
                }
            }
        }
    }
    sessions.sort_by_key(|item| item.start_secs);
    Ok(ClassroomCatalog {
        course_id: course.into(),
        title: string(&data["title"], "catalog_title")?,
        teachers: array(&data["teachers"], "catalog_teachers_shape")?
            .iter()
            .map(|row| string(&row["realname"], "catalog_teacher_name"))
            .collect::<Result<_>>()?,
        term_name: string(&data["term_name"], "catalog_term_name")?,
        sessions,
    })
}
pub(super) fn session(data: &Value, mode: ConnectionMode) -> Result<ClassroomSession> {
    let raw = text(&data["sub_status"], "session_status")?;
    let mut sources = Vec::new();
    let mut state = status(raw, &data["playback_status"]);
    if raw == "1" {
        for (key, kind) in [
            ("output", PlaybackKind::Teacher),
            ("output_student", PlaybackKind::Student),
        ] {
            if let Some(url) = data["live_url"][key]["m3u8"]
                .as_str()
                .and_then(|raw| media_url(raw, "lmt9.buaa.edu.cn", mode))
            {
                sources.push(PlaybackSource {
                    kind,
                    url,
                    duration_secs: None,
                    time_offset_secs: None,
                    resource_guid: None,
                });
            }
        }
        if sources.is_empty() {
            return Err(changed(STAGE, "live_sources_missing"));
        }
    } else if raw == "6" {
        let videos = object(&data["video_list"], "replay_video_list_shape")?;
        for row in videos.values() {
            let kind = match text(&row["type"], "replay_video_type")? {
                "2" => PlaybackKind::Slides,
                "3" => PlaybackKind::Teacher,
                _ => continue,
            };
            let Some(url) = row["preview_url"]
                .as_str()
                .and_then(|raw| media_url(raw, super::RESOURCE, mode))
            else {
                continue;
            };
            let resource = row["resource_guid"]
                .as_str()
                .filter(|value| guid(value))
                .ok_or_else(|| changed(STAGE, "replay_resource_guid"))?;
            sources.push(PlaybackSource {
                kind,
                url,
                duration_secs: Some(unsigned(&row["duration"], "replay_duration")?),
                time_offset_secs: Some(int(&row["time_offset"], "replay_time_offset")?),
                resource_guid: Some(resource.into()),
            });
        }
        let fallback = data["playurl"]["0"].as_str().filter(|raw| !raw.is_empty());
        if !sources
            .iter()
            .any(|source| source.kind == PlaybackKind::Teacher)
            && let Some(url) = fallback.and_then(|raw| media_url(raw, super::RESOURCE, mode))
        {
            sources.push(PlaybackSource {
                kind: PlaybackKind::Teacher,
                url,
                duration_secs: None,
                time_offset_secs: None,
                resource_guid: None,
            });
        }
        if sources.is_empty() && (!videos.is_empty() || fallback.is_some()) {
            return Err(changed(STAGE, "replay_sources_untrusted"));
        }
        state = if sources.is_empty() {
            ClassroomStatus::NoReplay
        } else {
            ClassroomStatus::Replay
        };
    }
    Ok(ClassroomSession {
        title: string(&data["sub_title"], "session_title")?,
        start_secs: int(&data["start_at"], "session_start")?,
        end_secs: int(&data["end_at"], "session_end")?,
        status: state,
        sources,
    })
}
fn millis(value: &Value) -> Result<u64> {
    let secs = value
        .as_f64()
        .or_else(|| value.as_str()?.parse().ok())
        .ok_or_else(|| changed(STAGE, "transcript_seconds_shape"))?;
    u64::try_from(
        std::time::Duration::try_from_secs_f64(secs)
            .map_err(|_| changed(STAGE, "transcript_seconds_range"))?
            .as_millis(),
    )
    .map_err(|_| changed(STAGE, "transcript_millis_range"))
}
pub(super) fn transcript(body: &Value) -> Result<Transcript> {
    let mut segments = Vec::new();
    if let Some(first) = array(&body["list"], "transcript_list_shape")?.first() {
        for row in array(&first["all_content"], "transcript_content_shape")? {
            segments.push(TranscriptSegment {
                begin_ms: millis(&row["BeginSec"])?,
                end_ms: millis(&row["EndSec"])?,
                text: string(&row["Text"], "transcript_text")?,
            });
        }
    }
    Ok(Transcript { segments })
}
pub(super) fn summary(body: &Value) -> Result<ClassSummary> {
    let mut result = ClassSummary::default();
    let mut seen = HashSet::new();
    for row in array(&body["result"]["data"], "summary_list_shape")? {
        let content = &row["content"];
        match text(&row["type"], "summary_type")? {
            "Summarization" => {
                result.summary =
                    Some(string(content, "summary_text")?).filter(|item| !item.is_empty());
            }
            "Keywords" => {
                result.keywords = array(content, "summary_keywords_shape")?
                    .iter()
                    .map(|item| string(item, "summary_keyword_text"))
                    .collect::<Result<_>>()?;
            }
            "QA" | "Q&A" => {
                for item in array(content, "summary_qa_shape")? {
                    let qa = ClassQuestion {
                        question: string(&item["question"], "summary_question")?,
                        answer: string(&item["answer"], "summary_answer")?,
                        start_ms: unsigned(&item["start"], "summary_qa_start")?,
                    };
                    if seen.insert(qa.clone()) {
                        result.qa.push(qa);
                    }
                }
            }
            "AutoChapters" => {
                for item in array(content, "summary_chapters_shape")? {
                    result.chapters.push(ClassChapter {
                        start_ms: unsigned(&item["start"], "summary_chapter_start")?,
                        end_ms: unsigned(&item["end"], "summary_chapter_end")?,
                        headline: string(&item["headline"], "summary_chapter_headline")?,
                        summary: string(&item["summary"], "summary_chapter_text")?,
                    });
                }
            }
            _ => {}
        }
    }
    Ok(result)
}
pub(super) fn slides(body: &Value, mode: ConnectionMode) -> Result<SlideTimeline> {
    let mut slides = Vec::new();
    for row in array(&body["list"], "slides_list_shape")? {
        let content: Value = serde_json::from_str(text(&row["content"], "slide_content_shape")?)
            .map_err(|_| changed(STAGE, "slide_content_json"))?;
        let link = |key: &str, reason| {
            content[key]
                .as_str()
                .and_then(|value| media_url(value, super::RESOURCE, mode))
                .ok_or_else(|| changed(STAGE, reason))
        };
        let image_url = link("pptimgurl", "slide_image_untrusted")?;
        let thumb_url = link("pptthumb", "slide_thumbnail_untrusted")?;
        let parsed =
            url::Url::parse(&image_url).map_err(|_| changed(STAGE, "slide_image_url_invalid"))?;
        let offset_ms = parsed
            .path()
            .rsplit('/')
            .next()
            .and_then(|name| name.strip_suffix(".jpg"))
            .filter(|name| digits(name))
            .and_then(|name| name.parse().ok())
            .ok_or_else(|| changed(STAGE, "slide_offset_invalid"))?;
        slides.push(ClassSlide {
            offset_ms,
            image_url,
            thumb_url,
        });
    }
    slides.sort_by_key(|item| item.offset_ms);
    Ok(SlideTimeline { slides })
}
