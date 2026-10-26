use ubaa_core::facade::{
    CacheError, CacheKey, CacheLimits, CachedGradeScoreBaseline, CachedGradeScoreEntry,
    ConnectionMode, OfflineCache,
};
use ubaa_core::facade::{CachePayload, CacheQuery};

const ACCOUNT: &str = "0123456789abcdef0123456789abcdef";
const TERM: &str = "2026-2027-1";

fn baseline(term: &str, score: &str) -> CachedGradeScoreBaseline {
    CachedGradeScoreBaseline {
        term_code: term.into(),
        term_name: "合成独立学期".into(),
        scores: vec![CachedGradeScoreEntry {
            key: "code:synthetic-grade-only".into(),
            course_name: Some("合成课程正文不得明文出现".into()),
            course_code: Some("synthetic-grade-only".into()),
            score: Some(score.into()),
        }],
    }
}

fn open(root: &std::path::Path, account: &str) -> OfflineCache {
    std::fs::create_dir_all(root).unwrap();
    OfflineCache::open(
        root,
        account,
        "合成账号",
        CacheKey::new([19; 32]),
        CacheLimits {
            soft_bytes: 100_000,
            hard_bytes: 100_000,
        },
    )
    .unwrap()
}

#[test]
fn 成绩基线是独立精确学期的加密白名单载荷() {
    let query = serde_json::from_value::<CacheQuery>(serde_json::json!({
        "GradeScoreBaseline": { "term": "2026-2027-1" }
    }));
    assert!(query.is_ok(), "成绩变化基线必须进入Core统一范围合同");
    let payload = serde_json::from_value::<CachePayload>(serde_json::json!({
        "GradeScoreBaseline": {
            "term_code": "2026-2027-1", "term_name": "合成学期",
            "scores": [{"key":"code:synthetic", "course_name":"合成课程", "course_code":"synthetic", "score":"89"}]
        }
    }));
    assert!(payload.is_ok(), "成绩基线必须由Core加密载荷承载");
}

#[test]
fn 成绩基线重开按账号路线学期隔离且磁盘无正文() {
    let root = super::test_root("grade-baseline-reopen");
    let cache = open(&root, ACCOUNT);
    let value = baseline(TERM, "synthetic-score-only");
    assert!(
        cache
            .update_grade_score_baseline(ConnectionMode::Direct, value.clone(), None)
            .unwrap()
            .is_none()
    );
    drop(cache);
    let cache = open(&root, ACCOUNT);
    assert_eq!(
        cache
            .read_grade_score_baseline(ConnectionMode::Direct, TERM)
            .unwrap(),
        Some(value.clone())
    );
    assert!(
        cache
            .read_grade_score_baseline(ConnectionMode::WebVpn, TERM)
            .unwrap()
            .is_none()
    );
    assert!(
        cache
            .read_grade_score_baseline(ConnectionMode::Direct, "2026-2027-2")
            .unwrap()
            .is_none()
    );
    let another = open(&root, "abcdef0123456789abcdef0123456789");
    assert!(
        another
            .read_grade_score_baseline(ConnectionMode::Direct, TERM)
            .unwrap()
            .is_none()
    );
    drop(another);
    let before = cache
        .update_grade_score_baseline(ConnectionMode::Direct, baseline(TERM, "90"), None)
        .unwrap();
    assert_eq!(before, Some(value));
    drop(cache);
    verify(&root);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 旧基线迁入不覆盖已有加密值且其他学期独立保留() {
    let root = super::test_root("grade-baseline-migrate");
    let cache = open(&root, ACCOUNT);
    let old = baseline(TERM, "70");
    let first = baseline(TERM, "80");
    assert_eq!(
        cache
            .update_grade_score_baseline(ConnectionMode::Direct, first.clone(), Some(old.clone()))
            .unwrap(),
        Some(old.clone())
    );
    assert_eq!(
        cache
            .update_grade_score_baseline(ConnectionMode::Direct, baseline(TERM, "90"), Some(old))
            .unwrap(),
        Some(first)
    );
    let history = baseline("2025-2026-2", "75");
    cache
        .update_grade_score_baseline(
            ConnectionMode::Direct,
            baseline(TERM, "95"),
            Some(history.clone()),
        )
        .unwrap();
    assert_eq!(
        cache
            .read_grade_score_baseline(ConnectionMode::Direct, "2025-2026-2")
            .unwrap(),
        Some(history)
    );
    drop(cache);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 空集合非法字段与容量失败保留原基线() {
    let root = super::test_root("grade-baseline-failure");
    let cache = open(&root, ACCOUNT);
    let old = baseline(TERM, "80");
    cache
        .update_grade_score_baseline(ConnectionMode::Direct, old.clone(), None)
        .unwrap();
    let mut empty = old.clone();
    empty.scores.clear();
    let mut invalid = old.clone();
    invalid.scores[0].key.clear();
    for value in [empty, invalid, baseline("unknown", "90")] {
        assert_eq!(
            cache.update_grade_score_baseline(ConnectionMode::Direct, value, None),
            Err(CacheError::InvalidInput)
        );
    }
    let mut huge = old.clone();
    huge.scores = vec![huge.scores[0].clone(); 4096];
    assert_eq!(
        cache.update_grade_score_baseline(ConnectionMode::Direct, huge, None),
        Err(CacheError::Capacity)
    );
    assert_eq!(
        cache
            .read_grade_score_baseline(ConnectionMode::Direct, TERM)
            .unwrap(),
        Some(old)
    );
    drop(cache);
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn 清理退出拒绝旧句柄保存且错误密钥不能读基线() {
    let root = super::test_root("grade-baseline-lifecycle");
    let cache = open(&root, ACCOUNT);
    cache
        .update_grade_score_baseline(ConnectionMode::Direct, baseline(TERM, "80"), None)
        .unwrap();
    assert!(
        OfflineCache::open(
            &root,
            ACCOUNT,
            "合成账号",
            CacheKey::new([29; 32]),
            CacheLimits::default()
        )
        .is_err()
    );
    let (next, _) = cache.clear_and_reopen().unwrap();
    assert_eq!(
        cache.update_grade_score_baseline(ConnectionMode::Direct, baseline(TERM, "90"), None),
        Err(CacheError::Superseded)
    );
    assert!(
        next.read_grade_score_baseline(ConnectionMode::Direct, TERM)
            .unwrap()
            .is_none()
    );
    next.deactivate().unwrap();
    assert_eq!(
        next.update_grade_score_baseline(ConnectionMode::Direct, baseline(TERM, "90"), None),
        Err(CacheError::Inactive)
    );
    drop((cache, next));
    std::fs::remove_dir_all(root).unwrap();
}

fn verify(path: &std::path::Path) {
    for item in std::fs::read_dir(path).unwrap() {
        let path = item.unwrap().path();
        if path.is_dir() {
            verify(&path);
            continue;
        }
        let bytes = std::fs::read(path).unwrap();
        for text in [
            "synthetic-grade-only",
            "synthetic-score-only",
            "合成课程正文不得明文出现",
            "2026-2027-1",
        ] {
            assert!(
                !bytes
                    .windows(text.len())
                    .any(|window| window == text.as_bytes())
            );
        }
    }
}
