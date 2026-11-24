use super::{
    auth::{check_business_response, resolve_required_spoc_result, with_spoc_auth_retry},
    files::{business_post, require_id, safe_name, url},
    list::{course_map, current_term},
    parser::parse_envelope,
};
use crate::{
    domain::{SpocCourse, SpocCourseFile},
    error::{Result, UbaaError},
    runtime::ClientRuntime,
};
use serde::Deserialize;

const ROOT: &str = "https://spoc.buaa.edu.cn/spocnewht/kcwj/queryListPageXs";
const FOLDER: &str = "https://spoc.buaa.edu.cn/spocnewht/grwj1/queryKcwjListgr";
const MAX_PAGES: u32 = 100;

pub(crate) async fn courses(runtime: &mut ClientRuntime) -> Result<Vec<SpocCourse>> {
    let term = current_term(runtime)
        .await?
        .mrxq
        .filter(|value| !value.is_empty())
        .ok_or_else(|| UbaaError::upstream_changed("SPOC 当前学期缺失"))?;
    let result = course_map(runtime, &term).await;
    let mut courses: Vec<_> = resolve_required_spoc_result(runtime, result)
        .await?
        .into_values()
        .map(|course| SpocCourse {
            course_id: course.kcid,
            name: course.kcmc,
            teacher: course.skjs,
        })
        .collect();
    courses.sort_by(|left, right| left.course_id.cmp(&right.course_id));
    Ok(courses)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Page {
    pages: u32,
    #[serde(rename = "hasNextPage")]
    has_next: bool,
    list: Vec<Item>,
}
#[derive(Deserialize)]
struct Item {
    id: String,
    wjmc: String,
    sfwjj: String,
    wjsize: Option<String>,
    wjhzm: Option<String>,
    czsj: Option<String>,
    sfkxz: Option<String>,
}
impl From<Item> for SpocCourseFile {
    fn from(item: Item) -> Self {
        Self {
            id: item.id,
            name: safe_name(&item.wjmc),
            is_folder: item.sfwjj == "1",
            size_text: item.wjsize,
            extension: item.wjhzm,
            uploaded_at_text: item.czsj,
            download_allowed: item.sfkxz.as_deref() != Some("0"),
        }
    }
}

pub(crate) async fn list(
    runtime: &mut ClientRuntime,
    course_id: &str,
    folder_id: Option<&str>,
) -> Result<Vec<SpocCourseFile>> {
    require_id(course_id)?;
    if let Some(id) = folder_id {
        require_id(id)?;
    }
    let mut items = Vec::new();
    for number in 1..=MAX_PAGES {
        let url = url(
            runtime,
            if folder_id.is_some() { FOLDER } else { ROOT },
            &[
                ("pageNum", &number.to_string()),
                ("pageSize", "50"),
                ("pid", folder_id.unwrap_or("0")),
                ("mcTab", ""),
                ("kcid", course_id),
                ("lmlxdm", ""),
                ("wjlx", ""),
            ],
        )?;
        let result = with_spoc_auth_retry(runtime, move |runtime, credential| {
            let request = business_post(url.clone(), credential);
            Box::pin(async move {
                let response = runtime.request(request).await?;
                check_business_response(&response)?;
                parse_envelope::<Page>(&crate::features::body(&response))
                    .map_err(|err| err.with_http_status(response.status))
            })
        })
        .await;
        let page = resolve_required_spoc_result(runtime, result).await?;
        items.extend(page.list.into_iter().map(SpocCourseFile::from));
        if !page.has_next || number >= page.pages {
            return Ok(items);
        }
    }
    Err(UbaaError::upstream_changed("SPOC 课程文件目录超过 100 页"))
}
