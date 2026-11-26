use super::{changed, digits, guid, media_url};
use crate::domain::spoc_classroom::{
    ClassChapter, ClassQuestion, ClassSlide, ClassSummary, ClassroomCatalog, ClassroomPeriod,
    ClassroomSession, ClassroomStatus, PlaybackKind, PlaybackSource, SlideTimeline, Transcript,
    TranscriptSegment,
};
use crate::{domain::ConnectionMode, error::Result};
use serde_json::Value;
use std::collections::HashSet;

fn text(value: &Value) -> Result<&str> {
    value.as_str().ok_or_else(changed)
}
fn string(value: &Value) -> Result<String> {
    Ok(text(value)?.to_owned())
}
fn int(value: &Value) -> Result<i64> {
    value
        .as_i64()
        .or_else(|| value.as_str()?.parse().ok())
        .ok_or_else(changed)
}
fn unsigned(value: &Value) -> Result<u64> {
    int(value)?.try_into().map_err(|_| changed())
}
fn array(value: &Value) -> Result<&Vec<Value>> {
    value.as_array().ok_or_else(changed)
}
fn object(value: &Value) -> Result<&serde_json::Map<String, Value>> {
    value.as_object().ok_or_else(changed)
}
fn status(raw: &str, replay: Option<&str>) -> ClassroomStatus {
    match (raw, replay) {
        ("1", _) => ClassroomStatus::Live,
        ("2", _) => ClassroomStatus::Upcoming,
        ("6", Some("1")) => ClassroomStatus::Replay,
        ("6", Some("0")) => ClassroomStatus::NoReplay,
        _ => ClassroomStatus::Other(raw.into()),
    }
}
pub(super) fn catalog(data: &Value, course: &str) -> Result<ClassroomCatalog> {
    if data["id"].as_str() != Some(course) {
        return Err(changed());
    }
    let mut sessions = Vec::new();
    for months in object(&data["sub_list"])?.values() {
        for days in object(months)?.values() {
            for group in object(days)?.values() {
                for item in array(group)? {
                    let title = text(&item["sub_title"])?;
                    let week = title
                        .strip_prefix('第')
                        .and_then(|tail| tail.split_once('周'))
                        .and_then(|(num, _)| digits(num).then(|| num.parse().ok()).flatten());
                    let sub = text(&item["id"])?;
                    if !digits(sub) {
                        return Err(changed());
                    }
                    sessions.push(ClassroomPeriod {
                        sub_id: sub.into(),
                        title: title.into(),
                        week,
                        start_secs: int(&item["class_begin"])?,
                        end_secs: int(&item["class_over"])?,
                        room: string(&item["room_name"])?,
                        lecturer: string(&item["lecturer_name"])?,
                        status: status(
                            text(&item["sub_status"])?,
                            item["playback_status"].as_str(),
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
        title: string(&data["title"])?,
        teachers: array(&data["teachers"])?
            .iter()
            .map(|row| string(&row["realname"]))
            .collect::<Result<_>>()?,
        term_name: string(&data["term_name"])?,
        sessions,
    })
}
pub(super) fn session(data: &Value, mode: ConnectionMode) -> Result<ClassroomSession> {
    let raw = text(&data["sub_status"])?;
    let mut sources = Vec::new();
    let mut state = status(raw, None);
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
            return Err(changed());
        }
    } else if raw == "6" {
        let videos = object(&data["video_list"])?;
        for row in videos.values() {
            let kind = match text(&row["type"])? {
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
            let resource = text(&row["resource_guid"])?;
            if !guid(resource) {
                return Err(changed());
            }
            sources.push(PlaybackSource {
                kind,
                url,
                duration_secs: Some(unsigned(&row["duration"])?),
                time_offset_secs: Some(int(&row["time_offset"])?),
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
            return Err(changed());
        }
        state = if sources.is_empty() {
            ClassroomStatus::NoReplay
        } else {
            ClassroomStatus::Replay
        };
    }
    Ok(ClassroomSession {
        title: string(&data["sub_title"])?,
        start_secs: int(&data["start_at"])?,
        end_secs: int(&data["end_at"])?,
        status: state,
        sources,
    })
}
fn millis(value: &Value) -> Result<u64> {
    let secs = value
        .as_f64()
        .or_else(|| value.as_str()?.parse().ok())
        .ok_or_else(changed)?;
    u64::try_from(
        std::time::Duration::try_from_secs_f64(secs)
            .map_err(|_| changed())?
            .as_millis(),
    )
    .map_err(|_| changed())
}
pub(super) fn transcript(body: &Value) -> Result<Transcript> {
    let mut segments = Vec::new();
    if let Some(first) = array(&body["list"])?.first() {
        for row in array(&first["all_content"])? {
            segments.push(TranscriptSegment {
                begin_ms: millis(&row["BeginSec"])?,
                end_ms: millis(&row["EndSec"])?,
                text: string(&row["Text"])?,
            });
        }
    }
    Ok(Transcript { segments })
}
pub(super) fn summary(body: &Value) -> Result<ClassSummary> {
    let mut result = ClassSummary::default();
    let mut seen = HashSet::new();
    for row in array(&body["result"]["data"])? {
        let content = &row["content"];
        match text(&row["type"])? {
            "Summarization" => {
                result.summary = Some(string(content)?).filter(|item| !item.is_empty());
            }
            "Keywords" => {
                result.keywords = array(content)?.iter().map(string).collect::<Result<_>>()?;
            }
            "QA" | "Q&A" => {
                for item in array(content)? {
                    let qa = ClassQuestion {
                        question: string(&item["question"])?,
                        answer: string(&item["answer"])?,
                        start_ms: unsigned(&item["start"])?,
                    };
                    if seen.insert(qa.clone()) {
                        result.qa.push(qa);
                    }
                }
            }
            "AutoChapters" => {
                for item in array(content)? {
                    result.chapters.push(ClassChapter {
                        start_ms: unsigned(&item["start"])?,
                        end_ms: unsigned(&item["end"])?,
                        headline: string(&item["headline"])?,
                        summary: string(&item["summary"])?,
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
    for row in array(&body["list"])? {
        let content: Value = serde_json::from_str(text(&row["content"])?).map_err(|_| changed())?;
        let link =
            |key: &str| media_url(text(&content[key])?, super::RESOURCE, mode).ok_or_else(changed);
        let image_url = link("pptimgurl")?;
        let thumb_url = link("pptthumb")?;
        let parsed = url::Url::parse(&image_url).map_err(|_| changed())?;
        let offset_ms = parsed
            .path()
            .rsplit('/')
            .next()
            .and_then(|name| name.strip_suffix(".jpg"))
            .filter(|name| digits(name))
            .and_then(|name| name.parse().ok())
            .ok_or_else(changed)?;
        slides.push(ClassSlide {
            offset_ms,
            image_url,
            thumb_url,
        });
    }
    slides.sort_by_key(|item| item.offset_ms);
    Ok(SlideTimeline { slides })
}
