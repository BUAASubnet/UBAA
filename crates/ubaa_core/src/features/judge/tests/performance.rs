//! 显式运行的纯解析基准，不发送网络请求，也不对机器耗时设硬断言。
use super::parse_detail;
use std::fmt::Write as _;

#[test]
#[ignore = "手动比较首页批量详情解析耗时"]
fn 首页批量详情解析基准() {
    let mut rows = String::new();
    for n in 1..=40 {
        write!(
            rows,
            "<tr><td>{n}</td><td>合成题目{n}</td><td>2.5</td><td>已提交 得分：2</td></tr>"
        )
        .unwrap();
    }
    let html = format!(
        "<html><body>作业满分：100，共40道题，作业时间：2026-10-01 08:00 至 2026-11-01 08:00<table>{rows}</table></body></html>"
    );
    let started = std::time::Instant::now();
    for _ in 0..96 {
        let detail = parse_detail(
            std::hint::black_box(&html),
            "1",
            "合成课程",
            "1",
            "合成作业",
        )
        .unwrap();
        assert_eq!(detail.problems.len(), 40);
        assert_eq!(detail.submitted_count, 40);
        assert_eq!(detail.my_score.as_deref(), Some("80"));
        std::hint::black_box(detail);
    }
    eprintln!("96 份详情、每份 40 题：{}ms", started.elapsed().as_millis());
}
