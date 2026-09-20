use super::{activate, array, integer, invalid, number, post, require_term, required, table, text};
use crate::domain::{
    ExamArrangement, Grade, GradeOverview, GradeStatistics, GradeTermStatistics, Term,
};
use crate::error::{ErrorCode, ErrorKind, Result, UbaaError};
use crate::runtime::ClientRuntime;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

pub(crate) async fn grades(runtime: &mut ClientRuntime) -> Result<GradeOverview> {
    activate(runtime, "wdcjapp").await?;
    let mut rows = Vec::new();
    let mut total = None;
    let mut page = 1;
    loop {
        let root = post(
            runtime,
            "wdcjapp",
            "modules/wdcj/xscjcx.do",
            Some(&[("pageSize", "12".into()), ("pageNumber", page.to_string())]),
        )
        .await?;
        let data = table(&root, "xscjcx")?;
        let count = integer(data, "totalSize")?;
        if !(0..=10_000).contains(&count)
            || total.is_some_and(|n| n != count)
            || integer(data, "pageNumber")? != page
        {
            return Err(invalid("成绩分页总数/页码"));
        }
        let count_len = usize::try_from(count).map_err(|_| invalid("totalSize"))?;
        let batch = array(data, "rows")?;
        if batch.len() > 12
            || (rows.len() < count_len && batch.is_empty())
            || rows.len() + batch.len() > count_len
        {
            return Err(invalid("成绩分页不完整"));
        }
        rows.extend(batch.iter().cloned());
        total = Some(count);
        if rows.len() == count_len {
            break;
        }
        page += 1;
    }
    let ids: BTreeSet<_> = rows
        .iter()
        .map(|r| required(r, "WID"))
        .collect::<Result<_>>()?;
    if ids.len() != rows.len() {
        return Err(invalid("成绩标识重复"));
    }
    let grades = if rows.is_empty() {
        Vec::new()
    } else {
        let dictionary = post(runtime, "wdcjapp", "modules/wdcj/cjfzdjcx.do", Some(&[])).await?;
        let dictionary = table(&dictionary, "cjfzdjcx")?;
        let levels = array(dictionary, "rows")?;
        if usize::try_from(integer(dictionary, "totalSize")?).ok() != Some(levels.len()) {
            return Err(invalid("成绩字典不完整"));
        }
        rows.iter()
            .map(|row| parse_grade(row, levels))
            .collect::<Result<Vec<_>>>()?
    };
    Ok(overview(grades))
}

fn parse_grade(row: &Value, levels: &[Value]) -> Result<Grade> {
    let term = required(row, "XNXQDM")?;
    require_term(&term).map_err(|_| invalid("XNXQDM"))?;
    let system = text(row, "CJFZDM");
    let raw = text(row, "CJ");
    let displayed = text(row, "CJXSZ").or_else(|| raw.clone());
    let mut matches = levels.iter().filter(|level| {
        text(level, "CJFZDM") == system
            && ((raw.is_some() && text(level, "DM") == raw)
                || (displayed.is_some() && text(level, "MC") == displayed))
    });
    let first = matches.next();
    let level = if matches.next().is_none() {
        first
    } else {
        None
    };
    let score = text(row, "CJXSZ")
        .or_else(|| level.and_then(|v| text(v, "MC")))
        .or(raw);
    let effective = text(row, "SFYX");
    if effective
        .as_deref()
        .is_some_and(|e| !matches!(e, "0" | "1"))
    {
        return Err(invalid("SFYX"));
    }
    let included = effective.as_deref() != Some("0")
        && matches!(system.as_deref(), Some("0" | "1"))
        && !matches!(score.as_deref(), Some("T" | "EX"));
    let numeric = if system.as_deref() == Some("0") {
        score
            .as_deref()
            .and_then(|s| s.parse::<f64>().ok())
            .filter(|s| s.is_finite() && (0.0..=100.0).contains(s))
    } else {
        None
    };
    let grade_point = if !included {
        None
    } else if system.as_deref() == Some("0") {
        numeric.map(|score| {
            if score < 60.0 {
                0.0
            } else {
                4.0 - 3.0 * (100.0 - score).powi(2) / 1600.0
            }
        })
    } else {
        level
            .and_then(|v| number(v, "DYJDZ"))
            .filter(|n| (0.0..=4.0).contains(n))
    };
    let average_score = if included {
        numeric.or_else(|| {
            level
                .and_then(|v| number(v, "DYBFZCJ"))
                .filter(|n| (0.0..=100.0).contains(n))
        })
    } else {
        None
    };
    let credit = number(row, "XF");
    if credit.is_some_and(|n| n < 0.0) {
        return Err(invalid("XF"));
    }
    Ok(Grade {
        graduate: true,
        term_name: Some(text(row, "XNXQDM_DISPLAY").unwrap_or_else(|| term.clone())),
        average_score,
        course_name: Some(required(row, "KCMC")?),
        course_code: text(row, "KCDM"),
        credit,
        score,
        grade_point: grade_point.map(|p| p.to_string()),
        course_type: text(row, "KCLBMC").or_else(|| text(row, "KCLBDM_DISPLAY")),
        score_type: system,
        term_code: Some(term),
    })
}

fn statistics<'a>(grades: impl Iterator<Item = &'a Grade>) -> GradeStatistics {
    let mut result = GradeStatistics::default();
    let (mut points, mut scores) = (0.0, 0.0);
    for grade in grades {
        let Some(credit) = grade.credit.filter(|n| *n > 0.0 && n.is_finite()) else {
            continue;
        };
        if let Some(point) = grade
            .grade_point
            .as_deref()
            .and_then(|p| p.parse::<f64>().ok())
            .filter(|n| n.is_finite())
        {
            points += point * credit;
            result.gpa_credits += credit;
        }
        if let Some(score) = grade.average_score.filter(|n| n.is_finite()) {
            scores += score * credit;
            result.average_credits += credit;
        }
    }
    result.gpa = (result.gpa_credits > 0.0)
        .then(|| points / result.gpa_credits)
        .filter(|v| v.is_finite());
    result.average_score = (result.average_credits > 0.0)
        .then(|| scores / result.average_credits)
        .filter(|v| v.is_finite());
    result
}

fn overview(grades: Vec<Grade>) -> GradeOverview {
    let mut grouped: BTreeMap<String, Vec<&Grade>> = BTreeMap::new();
    for grade in &grades {
        grouped
            .entry(grade.term_code.clone().unwrap_or_default())
            .or_default()
            .push(grade);
    }
    let terms = grouped
        .into_iter()
        .rev()
        .map(|(term_code, group)| GradeTermStatistics {
            term_name: group[0]
                .term_name
                .clone()
                .unwrap_or_else(|| term_code.clone()),
            term_code,
            statistics: statistics(group.into_iter()),
        })
        .collect();
    GradeOverview {
        graduate: true,
        statistics: Some(statistics(grades.iter())),
        grades,
        terms,
    }
}

pub(crate) async fn exam_terms(runtime: &mut ClientRuntime) -> Result<Vec<Term>> {
    activate(runtime, "wdksapp").await?;
    let root = post(
        runtime,
        "wdksapp",
        "modules/ksxxck/getXnxqList.do",
        Some(&[]),
    )
    .await?;
    parse_exam_terms(&root)
}

fn parse_exam_terms(root: &Value) -> Result<Vec<Term>> {
    let mut result = Vec::new();
    for row in array(root, "datas")? {
        let code = required(row, "DM")?;
        require_term(&code).map_err(|_| invalid("DM"))?;
        result.push(Term {
            item_code: code,
            item_name: required(row, "MC")?,
            selected: text(row, "SFDQXQ").as_deref() == Some("1"),
            item_index: 0,
        });
    }
    result.sort_by(|a, b| b.item_code.cmp(&a.item_code));
    if result.windows(2).any(|w| w[0].item_code == w[1].item_code) {
        return Err(invalid("考试学期重复"));
    }
    for (i, term) in result.iter_mut().enumerate() {
        term.item_index = i32::try_from(i).map_err(|_| invalid("学期数量"))?;
    }
    Ok(result)
}

pub(crate) async fn exams(runtime: &mut ClientRuntime, term: &str) -> Result<ExamArrangement> {
    require_term(term)?;
    activate(runtime, "wdksapp").await?;
    let root = post(
        runtime,
        "wdksapp",
        "modules/ksxxck/getWdksxx.do",
        Some(&[("xnxqdm", term.into())]),
    )
    .await?;
    parse_exams(&root)
}

fn parse_exams(root: &Value) -> Result<ExamArrangement> {
    if root.get("success").and_then(Value::as_bool) != Some(true) {
        return Err(invalid("success"));
    }
    let counts = [
        integer(root, "countKs")?,
        integer(root, "countKcks")?,
        integer(root, "countJk")?,
    ];
    if counts.iter().any(|n| *n < 0) {
        return Err(invalid("考试计数"));
    }
    if counts.iter().any(|n| *n > 0) {
        return Err(UbaaError::new(
            ErrorCode::Unsupported,
            ErrorKind::Upstream,
            false,
            "学校已返回考试记录，当前版本尚未适配明细，请到 GSMIS 我的考试安排查看",
        ));
    }
    Ok(ExamArrangement::default())
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;
    #[test]
    fn gsmis_grade_boundaries_and_independent_denominators() {
        let row = |score: &str, system: &str| serde_json::json!({"WID":"fixture","XNXQDM":"20261","KCMC":"Fixture","XF":2,"CJXSZ":score,"CJFZDM":system});
        let mut grades = Vec::new();
        for (score, expected) in [("59", "0"), ("60", "1"), ("100", "4")] {
            let g = parse_grade(&row(score, "0"), &[]).unwrap();
            assert_eq!(g.grade_point.as_deref(), Some(expected));
            grades.push(g);
        }
        let levels = [serde_json::json!({"CJFZDM":"1","MC":"Pass","DYBFZCJ":60})];
        grades.push(parse_grade(&row("Pass", "1"), &levels).unwrap());
        grades.push(parse_grade(&row("EX", "5"), &[]).unwrap());
        let stats = statistics(grades.iter());
        assert!((stats.gpa_credits - 6.0).abs() < f64::EPSILON);
        assert!((stats.average_credits - 8.0).abs() < f64::EPSILON);
        assert!(statistics([].iter()).gpa.is_none());
        assert!(
            parse_grade(&row("90", "7"), &[])
                .unwrap()
                .grade_point
                .is_none()
        );
    }
    #[test]
    fn gsmis_nonempty_or_unknown_exams_never_become_empty() {
        assert!(
            parse_exams(&serde_json::json!({"success":true,"countKs":0,"countKcks":0})).is_err()
        );
        let error =
            parse_exams(&serde_json::json!({"success":true,"countKs":1,"countKcks":0,"countJk":0}))
                .unwrap_err();
        assert!(error.message.contains("尚未适配明细"));
        assert_eq!(serde_json::to_value(error.code).unwrap(), "unsupported");
    }
}
