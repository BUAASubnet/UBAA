//! Empty classroom response parser and verified request constants.
#![allow(clippy::missing_errors_doc)]

use std::collections::BTreeMap;

use serde::Deserialize;

use crate::domain::{ClassroomInfo, ClassroomQuery};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};

/// Classroom query endpoint.
pub const CLASSROOM_URL: &str = "https://app.buaa.edu.cn/buaafreeclass/wap/default/search1";
/// Session synchronization URL observed in the old implementation.
pub const CLASSROOM_SYNC_URL: &str = "https://sso.buaa.edu.cn/login?service=https%3A%2F%2Fapp.buaa.edu.cn%2Fa_buaa%2Fapi%2Fcas%2Findex%3Fredirect%3Dhttps%253A%252F%252Fapp.buaa.edu.cn%252Fsite%252FclassRoomQuery%252Findex%26from%3Dwap%26login_from%3D&noAutoRedirect=1";

#[derive(Debug, Deserialize)]
struct RawResponse {
    #[serde(rename = "e")]
    code: i32,
    #[serde(rename = "m", default)]
    message: String,
    #[serde(rename = "d", default)]
    data: RawData,
}

#[derive(Debug, Default, Deserialize)]
struct RawData {
    #[serde(default)]
    list: BTreeMap<String, Vec<RawClassroom>>,
}

#[derive(Debug, Deserialize)]
struct RawClassroom {
    id: String,
    #[serde(rename = "floorid")]
    floor_id: String,
    name: String,
    #[serde(rename = "kxsds")]
    available_sections: String,
}

/// Parse a classroom `e/m/d` wrapper, including a valid empty list.
pub fn parse_response(body: &str) -> Result<ClassroomQuery> {
    let response: RawResponse = serde_json::from_str(body).map_err(|_| {
        UbaaError::new(
            ErrorCode::ParseError,
            ErrorKind::Parse,
            false,
            "classroom response is not valid JSON",
        )
    })?;
    if response.code != 0 {
        return Err(UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "classroom response returned a nonzero code",
        ));
    }
    Ok(ClassroomQuery {
        code: response.code,
        message: response.message,
        floors: response
            .data
            .list
            .into_iter()
            .map(|(floor, rooms)| {
                (
                    floor,
                    rooms
                        .into_iter()
                        .map(|room| ClassroomInfo {
                            id: room.id,
                            floor_id: room.floor_id,
                            name: room.name,
                            available_sections: room.available_sections,
                        })
                        .collect(),
                )
            })
            .collect(),
    })
}

/// Query free classrooms for a campus and ISO date.
pub(crate) async fn search(
    runtime: &mut crate::runtime::ClientRuntime,
    campus_id: i32,
    date: &str,
) -> Result<ClassroomQuery> {
    if date.len() != 10
        || date.as_bytes().get(4) != Some(&b'-')
        || date.as_bytes().get(7) != Some(&b'-')
    {
        return Err(UbaaError::new(
            ErrorCode::InvalidInput,
            ErrorKind::Input,
            false,
            "date must use yyyy-mm-dd",
        ));
    }
    let sync = super::get_with_redirects(
        runtime,
        runtime.url(CLASSROOM_SYNC_URL)?,
        &[("User-Agent", "Mozilla/5.0")],
        "classroom",
    )
    .await?;
    super::check_response(&sync, "classroom")?;
    let mut url = url::Url::parse(&runtime.url(CLASSROOM_URL)?).map_err(|_| {
        UbaaError::new(
            ErrorCode::UpstreamChanged,
            ErrorKind::Upstream,
            false,
            "classroom URL is invalid",
        )
    })?;
    url.query_pairs_mut()
        .append_pair("xqid", &campus_id.to_string())
        .append_pair("floorid", "")
        .append_pair("date", date);
    let response = super::get_with_redirects(
        runtime,
        url.to_string(),
        &[
            ("User-Agent", "Mozilla/5.0"),
            ("Accept", "application/json, text/javascript, */*; q=0.01"),
            ("X-Requested-With", "XMLHttpRequest"),
            (
                "Referer",
                "https://app.buaa.edu.cn/site/classRoomQuery/index",
            ),
        ],
        "classroom",
    )
    .await?;
    super::check_response(&response, "classroom")?;
    parse_response(&super::body(&response))
}
