//! 学校投影与 facade 回归共用的脱敏载荷。日期范围和缓存元数据由合成上下文构造。
use crate::{
    cache::{CacheCompleteness, CachePayload, CacheQuery, CacheRecord, CacheScope},
    domain::{ConnectionMode, agenda::AgendaTime},
};
#[derive(serde::Deserialize)]
struct Fixture {
    now: String,
    records: Vec<FixtureRecord>,
}
#[derive(serde::Deserialize)]
struct FixtureRecord {
    payload: CachePayload,
}
pub(crate) fn school_fixture() -> (Vec<CacheRecord>, AgendaTime) {
    let fixture: Fixture = serde_json::from_str(include_str!(
        "../../../../fixtures/readonly/agenda_school.json"
    ))
    .unwrap();
    let now = AgendaTime::new(fixture.now.parse().unwrap());
    let records = fixture
        .records
        .into_iter()
        .map(|record| {
            let query = match &record.payload {
                CachePayload::BykcChosen(_) => CacheQuery::BykcChosen,
                CachePayload::SpocAssignments(v) => CacheQuery::SpocTerm {
                    term: v.term_code.clone(),
                },
                CachePayload::JudgeSummaries(_) => CacheQuery::JudgeSummaries {
                    include_expired: false,
                },
                CachePayload::CgyyOrders(v) => CacheQuery::CgyyOrders {
                    page: v.number,
                    size: v.size,
                },
                CachePayload::SigninToday(_) => CacheQuery::SigninToday {
                    date: now.datetime.format("%Y%m%d").to_string(),
                },
                CachePayload::Exams(_) => CacheQuery::Exams {
                    term: "synthetic-term".into(),
                },
                CachePayload::YgdkOverview(v) => CacheQuery::YgdkOverviewPeriod {
                    classify_id: v.classify_id,
                    term_id: v.summary.term_id,
                    week_start: "2026-03-23".into(),
                },
                _ => panic!("日程夹具只包含已声明的公开来源"),
            };
            CacheRecord {
                scope: CacheScope {
                    route: ConnectionMode::Direct,
                    query,
                },
                payload: record.payload,
                fetched_at: 1,
                last_attempt_at: 1,
                last_verified_at: 1,
                last_attempt_succeeded: true,
                revision: 1,
                completeness: CacheCompleteness::Complete,
            }
        })
        .collect();
    (records, now)
}
