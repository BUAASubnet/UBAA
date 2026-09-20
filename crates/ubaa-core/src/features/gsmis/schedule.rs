use super::{activate, array, integer, invalid, post, require_term, required, table, text};
use crate::domain::{CourseClass, SectionTime, Term, TodayClass, Week, WeeklySchedule};
use crate::error::Result;
use crate::runtime::ClientRuntime;
use chrono::{Datelike, Days, NaiveDate};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

pub(crate) async fn terms(runtime: &mut ClientRuntime) -> Result<Vec<Term>> {
    activate(runtime, "wdkbapp").await?;
    let root = post(runtime, "wdkbapp", "modules/xskcb/kfdxnxqcx.do", None).await?;
    parse_terms(&root)
}

fn parse_terms(root: &Value) -> Result<Vec<Term>> {
    let data = table(root, "kfdxnxqcx")?;
    let rows = array(data, "rows")?;
    if usize::try_from(integer(data, "totalSize")?).ok() != Some(rows.len()) {
        return Err(invalid("课表学期不完整"));
    }
    let mut terms = BTreeMap::new();
    for row in rows {
        let code = required(row, "XNXQDM")?;
        require_term(&code).map_err(|_| invalid("XNXQDM"))?;
        terms
            .entry(code)
            .or_insert(required(row, "XNXQDM_DISPLAY")?);
    }
    terms
        .into_iter()
        .rev()
        .enumerate()
        .map(|(i, (code, name))| {
            Ok(Term {
                item_code: code,
                item_name: name,
                selected: i == 0,
                item_index: i32::try_from(i).map_err(|_| invalid("学期数量"))?,
            })
        })
        .collect()
}

pub(crate) async fn schedule(runtime: &mut ClientRuntime, term: &str) -> Result<Schedule> {
    require_term(term)?;
    let terms = terms(runtime).await?;
    let term = terms
        .into_iter()
        .find(|t| t.item_code == term)
        .ok_or_else(|| invalid("未返回所选学期"))?;
    let root = post(
        runtime,
        "wdkbapp",
        "bykb/loadXskbData.do",
        Some(&[
            ("ZC", String::new()),
            ("XNXQDM", term.item_code.clone()),
            ("XH", String::new()),
            ("XQDM", String::new()),
        ]),
    )
    .await?;
    parse_schedule(&root, term)
}

#[derive(Clone)]
struct Row {
    class: CourseClass,
    mask: String,
    scheme: Option<String>,
    teacher_key: Option<String>,
}

pub(crate) struct Schedule {
    term: Term,
    rows: Vec<Row>,
    start: Option<NaiveDate>,
    sections: Vec<SectionTime>,
}

#[allow(clippy::too_many_lines)] // Keep the linked course/slot/calendar validation together.
fn parse_schedule(root: &Value, term: Term) -> Result<Schedule> {
    if text(root, "code").as_deref() != Some("1") {
        return Err(invalid("课表code"));
    }
    let rows = array(root, "jgList")?;
    let courses = array(root, "rwList")?;
    let mut slots = Vec::new();
    for scheme in array(root, "jcfaList")? {
        slots.extend(array(scheme, "skjcList")?.iter());
    }
    let mut course_map = BTreeMap::new();
    for course in courses {
        if required(course, "XNXQDM")? != term.item_code {
            return Err(invalid("课表学期不匹配"));
        }
        course_map
            .entry(required(course, "BJDM")?)
            .or_insert(course);
    }
    let mut parsed = Vec::new();
    let mut offsets: BTreeMap<String, u64> = BTreeMap::new();
    for row in rows {
        let class_id = required(row, "BJDM")?;
        let course = course_map
            .get(&class_id)
            .ok_or_else(|| invalid("排课缺少课程关联"))?;
        let day = integer(row, "XQ")?;
        let begin = integer(row, "KSJCDM")?;
        let end = integer(row, "JSJCDM")?;
        let mask = required(row, "ZCBH")?;
        if !(1..=7).contains(&day)
            || begin <= 0
            || end < begin
            || !mask.bytes().all(|c| matches!(c, b'0' | b'1'))
        {
            return Err(invalid("课表星期/节次/周次"));
        }
        if let Some(index) = mask.find('1') {
            let offset = u64::try_from(index)
                .ok()
                .and_then(|n| n.checked_mul(7))
                .and_then(|n| n.checked_add(u64::try_from(day - 1).ok()?))
                .ok_or_else(|| invalid("课表周次"))?;
            offsets
                .entry(class_id.clone())
                .and_modify(|old| *old = (*old).min(offset))
                .or_insert(offset);
        }
        let scheme = text(row, "JCFADM");
        let lookup = |section| -> Result<&Value> {
            let found: Vec<_> = slots
                .iter()
                .copied()
                .filter(|s| text(s, "JCFADM") == scheme && integer(s, "DM").ok() == Some(section))
                .collect();
            if found.len() != 1 {
                return Err(invalid("节次方案关联不唯一"));
            }
            Ok(found[0])
        };
        let begin_time = time(integer(lookup(begin)?, "KSSJ")?)?;
        let end_time = time(integer(lookup(end)?, "JSSJ")?)?;
        if begin_time >= end_time {
            return Err(invalid("课程时间顺序"));
        }
        let teacher = text(row, "JGJSXM");
        let teacher_key = teacher.as_ref().map(|s| {
            let mut names: Vec<_> = s.split(',').collect();
            names.sort_unstable();
            names.join(",")
        });
        parsed.push(Row {
            mask,
            scheme,
            teacher_key,
            class: CourseClass {
                course_code: required(row, "KCDM")?,
                course_name: required(row, "KCMC")?,
                course_serial_no: Some(class_id),
                credit: text(course, "XF"),
                begin_time: Some(begin_time),
                end_time: Some(end_time),
                begin_section: Some(begin),
                end_section: Some(end),
                place_name: text(row, "JASMC"),
                weeks_and_teachers: Some(
                    [text(row, "ZCMC"), teacher]
                        .into_iter()
                        .flatten()
                        .collect::<Vec<_>>()
                        .join(" "),
                ),
                day_of_week: Some(day),
                ..CourseClass::default()
            },
        });
    }
    let mut starts = BTreeSet::new();
    for course in courses {
        if let (Some(date), Some(offset)) = (
            text(course, "SCSKRQ"),
            offsets.get(&required(course, "BJDM")?),
        ) {
            let date =
                NaiveDate::parse_from_str(&date, "%Y-%m-%d").map_err(|_| invalid("SCSKRQ"))?;
            starts.insert(
                date.checked_sub_days(Days::new(*offset))
                    .ok_or_else(|| invalid("学期日期"))?,
            );
        }
    }
    if !rows.is_empty()
        && (starts.len() != 1
            || starts
                .first()
                .is_some_and(|s| s.weekday() != chrono::Weekday::Mon))
    {
        return Err(invalid("日期与周次无法一致对应"));
    }
    let schemes: BTreeSet<_> = parsed.iter().filter_map(|r| r.scheme.clone()).collect();
    let sections: BTreeSet<_> = slots
        .into_iter()
        .filter(|s| schemes.is_empty() || text(s, "JCFADM").is_some_and(|v| schemes.contains(&v)))
        .map(parse_section)
        .collect::<Result<_>>()?;
    Ok(Schedule {
        term,
        rows: parsed,
        start: starts.first().copied(),
        sections: sections.into_iter().collect(),
    })
}

fn time(value: i32) -> Result<String> {
    if !(0..=23).contains(&(value / 100)) || !(0..=59).contains(&(value % 100)) {
        return Err(invalid("节次时间"));
    }
    Ok(format!("{:02}:{:02}", value / 100, value % 100))
}

fn parse_section(value: &Value) -> Result<SectionTime> {
    let section = integer(value, "DM")?;
    let start_time = time(integer(value, "KSSJ")?)?;
    let end_time = time(integer(value, "JSSJ")?)?;
    if section <= 0 || start_time >= end_time {
        return Err(invalid("时间轴"));
    }
    Ok(SectionTime {
        section,
        start_time,
        end_time,
    })
}

impl Schedule {
    pub(crate) fn weeks(&self, today: NaiveDate) -> Result<Vec<Week>> {
        if self.rows.is_empty() {
            return Ok(Vec::new());
        }
        let start = self.start.ok_or_else(|| invalid("学期起点"))?;
        // ponytail: bitmap length is the queryable range, not an official term length.
        let length = self.rows.iter().map(|r| r.mask.len()).max().unwrap_or(0);
        (0..length)
            .map(|i| {
                let days = u64::try_from(i)
                    .ok()
                    .and_then(|n| n.checked_mul(7))
                    .ok_or_else(|| invalid("周次范围"))?;
                let from = start
                    .checked_add_days(Days::new(days))
                    .ok_or_else(|| invalid("周日期"))?;
                let to = from
                    .checked_add_days(Days::new(6))
                    .ok_or_else(|| invalid("周日期"))?;
                Ok(Week {
                    start_date: from.to_string(),
                    end_date: to.to_string(),
                    term: self.term.item_code.clone(),
                    cur_week: (from..=to).contains(&today),
                    serial_number: i32::try_from(i + 1).map_err(|_| invalid("周次"))?,
                    name: format!("第{}周", i + 1),
                })
            })
            .collect()
    }

    pub(crate) fn weekly(&self, week: i32) -> Result<WeeklySchedule> {
        let index = usize::try_from(week - 1).map_err(|_| invalid("周次必须大于0"))?;
        let mut groups: BTreeMap<Vec<Option<String>>, Vec<CourseClass>> = BTreeMap::new();
        for row in self
            .rows
            .iter()
            .filter(|r| r.mask.as_bytes().get(index) == Some(&b'1'))
        {
            let c = &row.class;
            let key = vec![
                c.course_serial_no.clone(),
                Some(c.course_code.clone()),
                c.day_of_week.map(|d| d.to_string()),
                c.place_name.clone(),
                row.teacher_key.clone(),
                Some(row.mask.clone()),
                row.scheme.clone(),
            ];
            groups.entry(key).or_default().push(c.clone());
        }
        let mut arranged_list = Vec::new();
        for mut group in groups.into_values() {
            group.sort_by_key(|c| {
                (
                    c.begin_section,
                    c.end_section,
                    c.begin_time.clone(),
                    c.end_time.clone(),
                )
            });
            group.dedup_by(|a, b| {
                (a.begin_section, a.end_section, &a.begin_time, &a.end_time)
                    == (b.begin_section, b.end_section, &b.begin_time, &b.end_time)
            });
            let mut merged: Vec<CourseClass> = Vec::new();
            for item in group {
                if let Some(previous) = merged
                    .last_mut()
                    .filter(|p| p.end_section.and_then(|n| n.checked_add(1)) == item.begin_section)
                {
                    previous.end_section = item.end_section;
                    previous.end_time = item.end_time;
                } else {
                    merged.push(item);
                }
            }
            arranged_list.extend(merged);
        }
        arranged_list.sort_by_key(|c| (c.day_of_week, c.begin_section, c.course_code.clone()));
        Ok(WeeklySchedule {
            arranged_list,
            code: self.term.item_code.clone(),
            name: self.term.item_name.clone(),
            section_times: self.sections.clone(),
        })
    }
}

pub(crate) fn current_date(runtime: &ClientRuntime) -> NaiveDate {
    chrono::DateTime::<chrono::Utc>::from(runtime.now())
        .with_timezone(&chrono_tz::Asia::Shanghai)
        .date_naive()
}

pub(crate) async fn today(runtime: &mut ClientRuntime) -> Result<Vec<TodayClass>> {
    let date = current_date(runtime);
    let mut result = Vec::new();
    let available = terms(runtime).await?;
    if let Some(term) = available
        .iter()
        .find(|term| term.selected)
        .or_else(|| available.first())
    {
        let semester = schedule(runtime, &term.item_code).await?;
        if let Some(week) = semester.weeks(date)?.iter().find(|w| w.cur_week) {
            result.extend(
                semester
                    .weekly(week.serial_number)?
                    .arranged_list
                    .into_iter()
                    .filter(|c| {
                        c.day_of_week == i32::try_from(date.weekday().number_from_monday()).ok()
                    })
                    .map(|c| TodayClass {
                        biz_name: c.course_name.clone(),
                        short_name: Some(c.course_name),
                        place: c.place_name,
                        time: c
                            .begin_time
                            .zip(c.end_time)
                            .map(|(begin, end)| format!("{begin}-{end}")),
                    }),
            );
        }
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn gsmis_review_malformed_selected_scheme_slot_rejects_schedule() {
        let mut root: Value =
            serde_json::from_str(crate::features::schedule::contract_tests::GSMIS_SCHEDULE)
                .unwrap();
        root["jcfaList"][0]["skjcList"][2]["KSSJ"] = serde_json::json!(1260);
        let term = Term {
            item_code: "20261".into(),
            ..Term::default()
        };
        assert!(parse_schedule(&root, term).is_err());
    }
    #[test]
    fn gsmis_schedule_rejects_inconsistent_calendar_and_preserves_empty_week_timeline() {
        let body = crate::features::schedule::contract_tests::GSMIS_SCHEDULE;
        let term = Term {
            item_code: "20261".into(),
            ..Term::default()
        };
        let data = parse_schedule(&serde_json::from_str(body).unwrap(), term.clone()).unwrap();
        assert_eq!(data.weekly(1).unwrap().section_times.len(), 3);
        assert!(data.weekly(1).unwrap().arranged_list.is_empty());
        for changed in [
            body.replace("2026-09-14", "2026-09-15"),
            body.replace("\"JSJCDM\":2", "\"JSJCDM\":4"),
            body.replace("20261", "20253"),
        ] {
            assert!(
                parse_schedule(&serde_json::from_str(&changed).unwrap(), term.clone()).is_err()
            );
        }
    }
}
