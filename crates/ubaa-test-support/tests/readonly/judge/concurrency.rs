use std::fmt::Write as _;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use ubaa_core::facade::testing::{HttpRequest, HttpResponse, HttpTransport};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, JudgeAssignmentKey, Result, RouteClient, UbaaError,
};

use super::JUDGE_LOGIN_URL;
use crate::common::{redirect_from, response, session_store_with};

#[derive(Clone)]
struct JudgeConcurrencyTransport {
    inflight: Arc<AtomicUsize>,
    max_inflight: Arc<AtomicUsize>,
}

impl JudgeConcurrencyTransport {
    fn new() -> Self {
        Self {
            inflight: Arc::new(AtomicUsize::new(0)),
            max_inflight: Arc::new(AtomicUsize::new(0)),
        }
    }

    fn max_inflight(&self) -> usize {
        self.max_inflight.load(Ordering::SeqCst)
    }
}

#[async_trait]
impl HttpTransport for JudgeConcurrencyTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let current = self.inflight.fetch_add(1, Ordering::SeqCst) + 1;
        self.max_inflight.fetch_max(current, Ordering::SeqCst);
        tokio::time::sleep(Duration::from_millis(5)).await;
        let result = if request.url
            == "https://sso.buaa.edu.cn/login?service=http%3A%2F%2Fjudge.buaa.edu.cn%2F"
        {
            Ok(redirect_from(&request.url, "https://judge.buaa.edu.cn/"))
        } else if request.url == "https://judge.buaa.edu.cn/" {
            Ok(response(200, &request.url, "judge home"))
        } else if request.url == "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" {
            let mut courses = String::new();
            for id in 1..=8 {
                let _ = write!(
                    courses,
                    r#"<a href="courselist.jsp?courseID={id}">Course {id}</a>"#
                );
            }
            Ok(response(200, &request.url, &courses))
        } else if request
            .url
            .starts_with("https://judge.buaa.edu.cn/courselist.jsp?courseID=")
        {
            Ok(response(200, &request.url, "selected"))
        } else if request.url == "https://judge.buaa.edu.cn/assignment/index.jsp" {
            Ok(response(
                200,
                &request.url,
                r#"<a href="assignment/index.jsp?assignID=1">Lab</a>"#,
            ))
        } else if request.url == "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=1" {
            Ok(response(
                200,
                &request.url,
                "作业满分:100 共 2 道 作业时间: 2026-08-01 08:00:00 至 2026-08-31 23:00:00 未提交",
            ))
        } else {
            Err(UbaaError::new(
                ErrorCode::InternalError,
                ErrorKind::Internal,
                false,
                "unexpected Judge concurrency request",
            ))
        };
        self.inflight.fetch_sub(1, Ordering::SeqCst);
        result
    }
}

#[tokio::test]
async fn judge_limits_course_queries_to_four_workers() {
    let transport = JudgeConcurrencyTransport::new();
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-concurrency-fixture"),
    )
    .expect("client");

    let result = client.judge_assignments(false).await.expect("Judge list");
    assert_eq!(result.data.len(), 8);
    assert!(
        observed.max_inflight() >= 2,
        "Judge course queries must run concurrently"
    );
    assert!(
        observed.max_inflight() <= 4,
        "Judge course query concurrency must stay bounded at four"
    );
}

#[tokio::test]
async fn judge_batch_details_preserve_input_order_with_four_workers() {
    let transport = JudgeConcurrencyTransport::new();
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-batch-concurrency-fixture"),
    )
    .expect("client");
    let keys = (1..=8)
        .map(|course_id| JudgeAssignmentKey {
            course_id: course_id.to_string(),
            assignment_id: "1".into(),
        })
        .collect::<Vec<_>>();

    let result = client
        .judge_assignment_details(&keys)
        .await
        .expect("Judge details");
    assert_eq!(result.data.len(), keys.len());
    for (detail, key) in result.data.iter().zip(&keys) {
        assert_eq!(detail.course_id, key.course_id);
        assert_eq!(detail.assignment_id, key.assignment_id);
    }
    assert!(
        observed.max_inflight() >= 2,
        "Judge detail queries must run concurrently"
    );
    assert!(
        observed.max_inflight() <= 4,
        "Judge detail query concurrency must stay bounded at four"
    );
}

#[derive(Clone, Default)]
struct JudgeGroupedBatchTransport {
    requests: Arc<Mutex<Vec<String>>>,
}

impl JudgeGroupedBatchTransport {
    fn request_count(&self, url: &str) -> usize {
        self.requests
            .lock()
            .expect("Judge grouped request log")
            .iter()
            .filter(|request| request.as_str() == url)
            .count()
    }
}

#[async_trait]
impl HttpTransport for JudgeGroupedBatchTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests
            .lock()
            .expect("Judge grouped request log")
            .push(request.url.clone());
        let body = match request.url.as_str() {
            url if url == JUDGE_LOGIN_URL => {
                return Ok(redirect_from(url, "https://judge.buaa.edu.cn/"));
            }
            "https://judge.buaa.edu.cn/" => "judge ready",
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=0" => {
                r#"<a href="courselist.jsp?courseID=1">Course 1</a>"#
            }
            "https://judge.buaa.edu.cn/courselist.jsp?courseID=1" => {
                // 给独立的键级 worker 留出时间观察同一个缺失缓存项。
                tokio::time::sleep(Duration::from_millis(10)).await;
                "selected"
            }
            "https://judge.buaa.edu.cn/assignment/index.jsp" => {
                r#"<a href="assignment/index.jsp?assignID=101">First</a>
                   <a href="assignment/index.jsp?assignID=102">Second</a>"#
            }
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101" => {
                "作业满分: 10 共 1 道 作业时间: 2026-08-01 08:00 至 2026-08-31 23:00 未提交"
            }
            "https://judge.buaa.edu.cn/assignment/index.jsp?assignID=102" => {
                "作业满分: 20 共 1 道 作业时间: 2026-08-02 08:00 至 2026-08-31 23:00 未提交"
            }
            _ => {
                return Err(UbaaError::new(
                    ErrorCode::InternalError,
                    ErrorKind::Internal,
                    false,
                    "unexpected grouped Judge request",
                ));
            }
        };
        Ok(response(200, &request.url, body))
    }
}

#[tokio::test]
async fn judge_same_course_batch_fetches_one_list_and_preserves_input_order() {
    let transport = JudgeGroupedBatchTransport::default();
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-grouped-batch-fixture"),
    )
    .expect("client");
    let keys = [
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "102".into(),
        },
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "101".into(),
        },
    ];

    let result = client
        .judge_assignment_details(&keys)
        .await
        .expect("grouped Judge details");

    assert_eq!(
        result
            .data
            .iter()
            .map(|detail| detail.assignment_id.as_str())
            .collect::<Vec<_>>(),
        ["102", "101"]
    );
    assert_eq!(
        observed.request_count("https://judge.buaa.edu.cn/assignment/index.jsp"),
        1,
        "one course worker must fetch and select the assignment list once"
    );
}

#[tokio::test]
async fn judge_batch_filters_blank_and_deduplicates_keys_in_first_seen_order() {
    let transport = JudgeGroupedBatchTransport::default();
    let observed = transport.clone();
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_with("judge-normalized-batch-fixture"),
    )
    .expect("client");
    let keys = [
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "102".into(),
        },
        JudgeAssignmentKey {
            course_id: " ".into(),
            assignment_id: "101".into(),
        },
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "102".into(),
        },
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "101".into(),
        },
    ];

    let result = client
        .judge_assignment_details(&keys)
        .await
        .expect("normalized Judge details");

    assert_eq!(
        result
            .data
            .iter()
            .map(|detail| detail.assignment_id.as_str())
            .collect::<Vec<_>>(),
        ["102", "101"],
        "the frozen normalization filters blank keys and keeps the first duplicate only"
    );
    assert_eq!(
        observed.request_count("https://judge.buaa.edu.cn/assignment/index.jsp"),
        1
    );
    assert_eq!(
        observed.request_count("https://judge.buaa.edu.cn/assignment/index.jsp?assignID=102"),
        1
    );
}

#[tokio::test]
async fn judge_clients_with_the_same_route_and_cookie_do_not_share_cache() {
    let first_transport = JudgeGroupedBatchTransport::default();
    let mut first = RouteClient::with_transport(
        ConnectionMode::Direct,
        first_transport,
        session_store_with("judge-client-isolation-fixture"),
    )
    .expect("first client");
    first
        .judge_assignment("1", "101")
        .await
        .expect("first Judge detail");

    let second_transport = JudgeGroupedBatchTransport::default();
    let observed_second = second_transport.clone();
    let mut second = RouteClient::with_transport(
        ConnectionMode::Direct,
        second_transport,
        session_store_with("judge-client-isolation-fixture"),
    )
    .expect("second client");
    second
        .judge_assignment("1", "101")
        .await
        .expect("second Judge detail");

    assert_eq!(
        observed_second.request_count("https://judge.buaa.edu.cn/courselist.jsp?courseID=0"),
        1,
        "a separately constructed client must fetch its own course cache"
    );
    assert_eq!(
        observed_second
            .request_count("https://judge.buaa.edu.cn/assignment/index.jsp?assignID=101"),
        1,
        "a separately constructed client must fetch its own detail cache"
    );
}
