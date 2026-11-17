use super::{business_path, invalid, score_url, year_label};
use crate::domain::{HealthCloudEvent, HealthCloudPage, HealthCloudReport, HealthCloudYear};
use crate::error::Result;
use scraper::{ElementRef, Html, Selector};

fn text(element: ElementRef<'_>) -> String {
    element.text().collect::<String>().trim().to_owned()
}

fn number(value: &str) -> Option<f64> {
    value.trim().parse::<f64>().ok().filter(|n| n.is_finite())
}

fn unit(value: &str, suffix: &str) -> Option<f64> {
    number(value.strip_suffix(suffix)?)
}

fn result_text(value: &str) -> Option<String> {
    (!value.is_empty()).then(|| value.to_owned())
}

fn years(doc: &Html, response_url: &str) -> (Vec<HealthCloudYear>, Option<String>) {
    let mut years: Vec<HealthCloudYear> = Vec::new();
    let mut selected = None;
    let base = score_url(None);
    let selector = Selector::parse("a[href]").expect("固定的 HTML 选择器");
    for link in doc.select(&selector) {
        let Some(href) = link.attr("href") else {
            continue;
        };
        // WebVPN 可能包装 href；转换后仍只收集健康云体测页的年份键。
        let Some(url) = [response_url, base.as_str()]
            .into_iter()
            .filter_map(|current| crate::connection::upstream_redirect_target(current, href).ok())
            .find(|url| {
                url.origin() == base.origin()
                    && url.path() == base.path()
                    && url.username().is_empty()
                    && url.password().is_none()
                    && url.fragment().is_none()
                    && business_path(url)
            })
        else {
            continue;
        };
        let Some((_, key)) = url.query_pairs().find(|(k, _)| k == "year") else {
            continue;
        };
        let Some(year) = year_label(&key) else {
            continue;
        };
        if text(link)
            .strip_suffix('年')
            .and_then(|s| s.parse::<u16>().ok())
            != Some(year)
        {
            continue;
        }
        if link
            .parent()
            .and_then(ElementRef::wrap)
            .is_some_and(|parent| {
                parent
                    .value()
                    .has_class("menu4l_active", scraper::CaseSensitivity::CaseSensitive)
            })
        {
            selected = Some(key.to_string());
        }
        if !years.iter().any(|y| y.key == key) {
            years.push(HealthCloudYear {
                year,
                key: key.into_owned(),
            });
        }
    }
    years.sort_by_key(|y| std::cmp::Reverse(y.year));
    (years, selected)
}

fn is_event(name: &str) -> bool {
    matches!(
        name,
        "1000米跑" | "800米跑" | "50米跑" | "立定跳远" | "引体向上" | "仰卧起坐"
    )
}

fn formatted_result(name: &str, value: &str) -> Option<String> {
    if matches!(name, "1000米跑" | "800米跑")
        && let Some((minutes, seconds)) = value.strip_suffix('分').and_then(|s| s.split_once('.'))
        && seconds.len() <= 2
        && let (Ok(minutes), Ok(seconds)) = (minutes.parse::<u16>(), seconds.parse::<u8>())
        && seconds < 60
    {
        return Some(format!("{minutes}′{seconds:02}″"));
    }
    result_text(value)
}

pub(super) fn parse(
    source: &str,
    requested_year: Option<&str>,
    response_url: &str,
) -> Result<HealthCloudPage> {
    let doc = Html::parse_document(source);
    let (years, active) = years(&doc, response_url);
    let rows = Selector::parse("table.table_bg > tbody > tr").expect("固定的 HTML 选择器");
    let mut report = HealthCloudReport::default();
    let mut page_year = None;
    let mut has_event_table = false;
    for row in doc.select(&rows) {
        let cells: Vec<_> = row.child_elements().map(text).collect();
        if cells.starts_with(&["测试年度".into()]) {
            page_year = cells.get(1).and_then(|v| v.parse::<u16>().ok());
        }
        if cells.starts_with(&["年级".into()]) {
            for pair in cells.as_chunks::<2>().0 {
                match pair[0].as_str() {
                    "身高" => report.height_cm = unit(&pair[1], "米").map(|m| m * 100.0),
                    "体重" => report.weight_kg = unit(&pair[1], "千克"),
                    _ => {}
                }
            }
        }
        if cells.first().is_some_and(|v| v == "项目") && cells.get(2).is_some_and(|v| v == "得分")
        {
            has_event_table = true;
            continue;
        }
        for [name, value, score, grade] in cells.as_chunks::<4>().0 {
            match name.as_str() {
                "身体机能(肺活量)" => report.lung_ml = unit(value, "毫升"),
                "坐立体前屈" => report.reach_cm = unit(value, "厘米"),
                name if is_event(name) => report.events.push(HealthCloudEvent {
                    name: name.to_owned(),
                    result: formatted_result(name, value),
                    score: number(score),
                    grade: result_text(grade),
                }),
                _ => {}
            }
        }
    }
    if years.is_empty() {
        return Err(invalid());
    }
    let selected_year = active.or_else(|| {
        years
            .iter()
            .find(|item| Some(item.year) == page_year)
            .map(|year| year.key.clone())
    });
    if requested_year.is_some() && requested_year != selected_year.as_deref()
        || (page_year.is_some()
            && (!has_event_table || selected_year.as_deref().and_then(year_label) != page_year))
    {
        return Err(invalid());
    }
    Ok(HealthCloudPage {
        years,
        selected_year,
        report: page_year.map(|_| report),
    })
}
