use super::{GraduateSchedule, Row, error};
use crate::domain::{CourseClass, Term, TodayClass, Week, WeeklySchedule};
use crate::error::Result;
use chrono::{Datelike, Days, NaiveDate};
use std::collections::{BTreeMap, BTreeSet};
impl GraduateSchedule {
    pub(in crate::features::schedule) fn terms(&self) -> Vec<Term> {
        self.terms.clone()
    }
    pub(in crate::features::schedule) fn weekly(&self, week: i32) -> Result<WeeklySchedule> {
        if week <= 0 {
            return Err(error());
        }
        let index = usize::try_from(week - 1).map_err(|_| error())?;
        let mut group_indices = BTreeMap::new();
        let mut groups: Vec<Vec<&Row>> = Vec::new();
        for row in self
            .rows
            .iter()
            .filter(|r| r.mask.as_bytes().get(index) == Some(&b'1'))
        {
            let teachers = row.teachers.as_ref().map(|t| {
                let mut names = t.split(',').collect::<Vec<_>>();
                names.sort_unstable();
                names.join(",")
            });
            let key = (
                row.course.course_serial_no.clone(),
                row.course.course_code.clone(),
                row.course.day_of_week,
                row.course.place_name.clone(),
                teachers,
                row.mask.clone(),
                row.scheme.clone(),
            );
            let group = *group_indices.entry(key).or_insert_with(|| {
                groups.push(Vec::new());
                groups.len() - 1
            });
            groups[group].push(row);
        }
        let mut classes = Vec::new();
        for mut group in groups {
            let mut seen = BTreeSet::new();
            group.retain(|r| {
                seen.insert((
                    r.course.begin_section,
                    r.course.end_section,
                    r.course.begin_time.clone(),
                    r.course.end_time.clone(),
                ))
            });
            group.sort_by_key(|r| r.course.begin_section);
            let mut merged: Vec<CourseClass> = Vec::new();
            for row in group {
                if let Some(previous) = merged.last_mut()
                    && previous.end_section.and_then(|v| v.checked_add(1))
                        == row.course.begin_section
                {
                    previous.end_section = row.course.end_section;
                    previous.end_time.clone_from(&row.course.end_time);
                    continue;
                }
                merged.push(row.course.clone());
            }
            classes.extend(merged);
        }
        classes.sort_by(|a, b| {
            (a.day_of_week, a.begin_section, &a.course_code).cmp(&(
                b.day_of_week,
                b.begin_section,
                &b.course_code,
            ))
        });
        let term = self
            .terms
            .iter()
            .find(|t| t.item_code == self.term)
            .ok_or_else(error)?;
        Ok(WeeklySchedule {
            arranged_list: classes,
            code: term.item_code.clone(),
            name: term.item_name.clone(),
            section_times: self.sections.clone(),
        })
    }
    pub(in crate::features::schedule) fn weeks(&self, today: &str) -> Result<Vec<Week>> {
        if self.rows.is_empty() {
            return Ok(Vec::new());
        }
        let today = NaiveDate::parse_from_str(today, "%Y-%m-%d").map_err(|_| error())?;
        let start = self.monday.ok_or_else(error)?;
        let count = self.rows.iter().map(|r| r.mask.len()).max().unwrap_or(0);
        (0..count)
            .map(|index| {
                let from = start
                    .checked_add_days(Days::new(u64::try_from(index).map_err(|_| error())? * 7))
                    .ok_or_else(error)?;
                let to = from.checked_add_days(Days::new(6)).ok_or_else(error)?;
                let number = i32::try_from(index + 1).map_err(|_| error())?;
                Ok(Week {
                    start_date: from.to_string(),
                    end_date: to.to_string(),
                    term: self.term.clone(),
                    cur_week: today >= from && today <= to,
                    serial_number: number,
                    name: format!("第{number}周"),
                })
            })
            .collect()
    }
    pub(in crate::features::schedule) fn today(&self, today: &str) -> Result<Vec<TodayClass>> {
        let Some(week) = self.weeks(today)?.into_iter().find(|w| w.cur_week) else {
            return Ok(Vec::new());
        };
        let day = NaiveDate::parse_from_str(today, "%Y-%m-%d")
            .map_err(|_| error())?
            .weekday()
            .number_from_monday();
        Ok(self
            .weekly(week.serial_number)?
            .arranged_list
            .into_iter()
            .filter(|c| c.day_of_week.and_then(|d| u32::try_from(d).ok()) == Some(day))
            .map(|c| TodayClass {
                biz_name: c.course_name.clone(),
                short_name: Some(c.course_name),
                place: c.place_name,
                time: Some(format!(
                    "{}-{}",
                    c.begin_time.unwrap_or_default(),
                    c.end_time.unwrap_or_default()
                )),
            })
            .collect())
    }
}
