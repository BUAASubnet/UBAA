use super::*;
use crate::domain::ConnectionMode;
use crate::ports::{HttpMethod, HttpRequest, HttpResponse, HttpTransport};
use crate::session::{SessionMutation, SessionSnapshot, SessionStore, VersionedSession};
use async_trait::async_trait;
use serde_json::json;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
struct Store(Arc<Mutex<VersionedSession>>);
impl SessionStore for Store {
    fn load_versioned(&self) -> Result<VersionedSession> {
        Ok(self.0.lock().unwrap().clone())
    }
    fn compare_exchange(
        &self,
        revision: u64,
        replacement: Option<&SessionSnapshot>,
    ) -> Result<SessionMutation> {
        let mut state = self.0.lock().unwrap();
        if state.revision != revision {
            return Ok(SessionMutation::Conflict);
        }
        state.revision += 1;
        state.snapshot = replacement.cloned();
        Ok(SessionMutation::Applied {
            revision: state.revision,
        })
    }
}
#[derive(Clone)]
struct Transport {
    identity: &'static str,
    requests: Arc<Mutex<Vec<HttpRequest>>>,
    duplicate: bool,
    nonempty_exam: bool,
}
#[async_trait]
impl HttpTransport for Transport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        self.requests.lock().unwrap().push(request.clone());
        let direct = crate::connection::from_webvpn_url(&request.url).unwrap();
        let url = url::Url::parse(&direct).unwrap();
        let value = if url.host_str() == Some("it.buaa.edu.cn") {
            assert_eq!(request.method, HttpMethod::Get);
            json!({"e":0,"d":{"info":{"identity":self.identity,"depart":"示例学院"}}})
        } else {
            assert_eq!(url.host_str(), Some("gsmis.buaa.edu.cn"));
            if url.path().ends_with("index.do") {
                return Ok(HttpResponse::new(
                    200,
                    request.url,
                    b"<html>ready</html>".to_vec(),
                ));
            }
            assert_eq!(request.method, HttpMethod::Post);
            assert_eq!(
                request.headers["Content-Type"],
                "application/x-www-form-urlencoded"
            );
            assert_eq!(request.headers["X-Requested-With"], "XMLHttpRequest");
            assert_eq!(
                request.headers["Referer"].starts_with("https://d.buaa.edu.cn/"),
                request.url.starts_with("https://d.buaa.edu.cn/")
            );
            if url.path().ends_with("xscjcx.do") {
                let page = if request.body == b"pageSize=12&pageNumber=1" {
                    1
                } else {
                    assert_eq!(request.body, b"pageSize=12&pageNumber=2");
                    2
                };
                let range = if page == 1 { 0..12 } else { 12..13 };
                json!({"code":"0","datas":{"xscjcx":{"totalSize":13,"pageNumber":page,"rows":range.map(|i|json!({"WID":if self.duplicate {"same".to_owned()} else {format!("row-{i}")},"XNXQDM":if i<12 {"20251"} else {"20261"},"XNXQDM_DISPLAY":"示例学期","KCMC":"示例课程","XF":2,"CJXSZ":"90","CJFZDM":"0"})).collect::<Vec<_>>()}}})
            } else if url.path().ends_with("cjfzdjcx.do") {
                assert_eq!(request.body.len(), 0);
                json!({"code":"0","datas":{"cjfzdjcx":{"totalSize":0,"rows":[]}}})
            } else if url.path().ends_with("getXnxqList.do") {
                assert_eq!(request.body.len(), 0);
                json!({"datas":[{"DM":"20261","MC":"考试学期","SFDQXQ":"1"}]})
            } else {
                assert!(url.path().ends_with("getWdksxx.do"));
                assert_eq!(request.body, b"xnxqdm=20261");
                json!({"success":true,"countKs":i32::from(self.nonempty_exam),"countKcks":0,"countJk":0})
            }
        };
        Ok(HttpResponse::new(
            200,
            request.url,
            serde_json::to_vec(&value).unwrap(),
        ))
    }
}
fn client(
    mode: ConnectionMode,
    identity: &'static str,
    duplicate: bool,
    nonempty_exam: bool,
) -> (ClientRuntime, Arc<Mutex<Vec<HttpRequest>>>) {
    let requests = Arc::new(Mutex::new(Vec::new()));
    let store = Store(Arc::new(Mutex::new(VersionedSession {
        revision: 1,
        snapshot: Some(SessionSnapshot {
            mode,
            cookies: vec![],
            authenticated_at: 1000,
            last_activity: 1001,
        }),
    })));
    (
        ClientRuntime::new(
            mode,
            Transport {
                identity,
                requests: requests.clone(),
                duplicate,
                nonempty_exam,
            },
            store,
        )
        .unwrap(),
        requests,
    )
}
#[tokio::test]
async fn 双路线研究生身份只请求一次并读取完整历史成绩和独立考试学期() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let (mut runtime, requests) = client(mode, "硕士研究生", false, false);
        let grades = crate::features::grades::get_overview(&mut runtime)
            .await
            .unwrap();
        assert_eq!(grades.grades.len(), 13);
        assert_eq!(grades.terms.len(), 2);
        let stats = grades.statistics.unwrap();
        assert_eq!(stats.gpa, Some(3.8125));
        assert_eq!(stats.average_score, Some(90.0));
        assert!((stats.gpa_credits - 26.0).abs() < f64::EPSILON);
        assert_eq!(
            crate::features::schedule::get_exam_terms(&mut runtime)
                .await
                .unwrap()[0]
                .item_code,
            "20261"
        );
        assert_eq!(
            crate::features::schedule::get_exam(&mut runtime, "20261")
                .await
                .unwrap()
                .arranged
                .len(),
            0
        );
        assert_eq!(
            requests
                .lock()
                .unwrap()
                .iter()
                .filter(|r| r.url.contains("/personal/frontend/data/info"))
                .count(),
            1
        );
        runtime.clear_feature_state();
        assert_eq!(identity(&mut runtime).await.unwrap(), StudentKind::Graduate);
        assert_eq!(
            requests
                .lock()
                .unwrap()
                .iter()
                .filter(|r| r.url.contains("/personal/frontend/data/info"))
                .count(),
            2
        );
    }
}
#[tokio::test]
async fn 未知身份不得查询教务且重复成绩不能返回部分结果() {
    let (mut runtime, requests) = client(ConnectionMode::Direct, "继续教育学生", false, false);
    assert_eq!(
        crate::features::grades::get_overview(&mut runtime)
            .await
            .unwrap_err()
            .code,
        ErrorCode::Unsupported
    );
    assert_eq!(requests.lock().unwrap().len(), 1);
    let (mut runtime, _) = client(ConnectionMode::Direct, "研究生", true, false);
    assert!(
        crate::features::grades::get_overview(&mut runtime)
            .await
            .is_err()
    );
    let (mut runtime, _) = client(ConnectionMode::Direct, "博士研究生", false, true);
    assert_eq!(
        crate::features::schedule::get_exam(&mut runtime, "20261")
            .await
            .unwrap_err()
            .code,
        ErrorCode::Unsupported
    );
}

#[tokio::test]
async fn 研究生不接受本科学期且不请求成绩系统() {
    let (mut runtime, requests) = client(ConnectionMode::Direct, "研究生", false, false);
    assert_eq!(
        crate::features::grades::get_grades(&mut runtime, "2025-2026-1")
            .await
            .unwrap_err()
            .code,
        ErrorCode::InvalidInput
    );
    assert_eq!(requests.lock().unwrap().len(), 1);
}
