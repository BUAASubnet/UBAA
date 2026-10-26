use std::sync::{Arc, Mutex};
use std::time::Duration;

use async_trait::async_trait;
use ubaa_core::facade::testing::{HttpRequest, HttpResponse, HttpTransport, from_webvpn_url};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, JudgeAssignmentKey, Result, RouteClient, UbaaError,
};

use crate::common::{response, session_store_for};

#[derive(Default)]
struct State {
    selected: String,
    expired: bool,
    wrong_service: bool,
}
#[derive(Clone, Copy, Default, Eq, PartialEq)]
enum Scenario {
    #[default]
    Normal,
    NativeLogin,
    StrictService,
    SharedCourses,
    MixedHistory,
    ExpireDetail,
}
#[derive(Clone, Default)]
struct JudgeRepairTransport {
    state: Arc<Mutex<State>>,
    scenario: Scenario,
}
#[async_trait]
impl HttpTransport for JudgeRepairTransport {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let direct = from_webvpn_url(&request.url).unwrap_or_else(|_| request.url.clone());
        let url = url::Url::parse(&direct).unwrap();
        if url.host_str() == Some("uc.buaa.edu.cn") {
            return Ok(response(
                200,
                &request.url,
                r#"{"code":0,"data":{"name":"测试用户","schoolid":"TEST-0001","username":"fixture-user"}}"#,
            ));
        }
        if url.host_str() == Some("sso.buaa.edu.cn") {
            let wrong = !url
                .query_pairs()
                .any(|(key, value)| key == "service" && value == "https://judge.buaa.edu.cn/");
            let mut state = self.state.lock().unwrap();
            state.selected.clear();
            state.wrong_service = self.scenario == Scenario::StrictService && wrong;
            if self.scenario == Scenario::NativeLogin || state.wrong_service {
                return Ok(response(
                    200,
                    "https://judge.buaa.edu.cn/indexcs/simple.jsp",
                    r#"<a id="cgstuloginbtn">校园统一认证登录</a>"#,
                ));
            }
            return Ok(response(200, "https://judge.buaa.edu.cn/", "已激活"));
        }
        if url.path() == "/courselist.jsp" {
            let course = url
                .query_pairs()
                .find(|(key, _)| key == "courseID")
                .unwrap()
                .1
                .into_owned();
            if course == "0" {
                if self.state.lock().unwrap().wrong_service {
                    return Ok(response(200, &request.url, ""));
                }
                let courses = if self.scenario == Scenario::SharedCourses {
                    r#"<a href="courselist.jsp?courseID=1">课程甲</a><a href="courselist.jsp?courseID=2">课程乙</a>"#
                } else {
                    r#"<a href="courselist.jsp?courseID=1">课程甲</a>"#
                };
                return Ok(response(200, &request.url, courses));
            }
            self.state.lock().unwrap().selected = course;
            tokio::time::sleep(Duration::from_millis(20)).await;
            return Ok(response(200, &request.url, "已选择"));
        }
        if url.path() == "/assignment/index.jsp" {
            let id = url
                .query_pairs()
                .find(|(key, _)| key == "assignID")
                .map(|(_, value)| value.into_owned());
            let mut state = self.state.lock().unwrap();
            if id.is_some() && self.scenario == Scenario::ExpireDetail && !state.expired {
                state.expired = true;
                state.selected.clear();
                return Ok(response(
                    200,
                    &request.url,
                    r#"<input name="execution">统一身份认证"#,
                ));
            }
            if self.scenario == Scenario::ExpireDetail && state.selected != "1" {
                return Err(UbaaError::new(
                    ErrorCode::UpstreamChanged,
                    ErrorKind::Upstream,
                    false,
                    "重新认证后没有恢复课程",
                ));
            }
            if let Some(id) = id {
                let start = if self.scenario == Scenario::MixedHistory && id == "102" {
                    "2000-01-01"
                } else {
                    "2099-01-01"
                };
                let body = format!(
                    "作业满分: 10 共 1 道 作业时间: {start} 08:00:00 至 2099-12-01 23:00:00 未提交"
                );
                return Ok(response(200, &request.url, &body));
            }
            let body = if self.scenario == Scenario::MixedHistory {
                r#"<a href="index.jsp?assignID=101">近期甲</a><a href="index.jsp?assignID=102">历史</a><a href="index.jsp?assignID=103">近期乙</a>"#.to_string()
            } else {
                format!(
                    r#"<a href="index.jsp?assignID={}01">测试作业</a>"#,
                    state.selected
                )
            };
            return Ok(response(200, &request.url, &body));
        }
        Err(UbaaError::new(
            ErrorCode::InternalError,
            ErrorKind::Internal,
            false,
            "未预期的合成请求",
        ))
    }
}

#[tokio::test]
async fn judge_官网https_service才能读取作业() {
    let transport = JudgeRepairTransport {
        scenario: Scenario::StrictService,
        ..Default::default()
    };
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_for(ConnectionMode::Direct, "judge-repair"),
    )
    .unwrap();
    assert_eq!(client.judge_assignments(false).await.unwrap().data.len(), 1);
}

#[tokio::test]
async fn judge_原生登录页不能作为空课程成功() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let transport = JudgeRepairTransport {
            scenario: Scenario::NativeLogin,
            ..Default::default()
        };
        let store = session_store_for(mode, "judge-native-login");
        let mut client = RouteClient::with_transport(mode, transport, store.clone()).unwrap();
        let error = client
            .judge_assignments(false)
            .await
            .expect_err("原生登录页必须失败");
        assert_eq!(error.code, ErrorCode::UpstreamUnavailable);
        assert!(store.snapshot().unwrap().is_some(), "UC有效时保留主会话");
    }
}

#[tokio::test]
async fn judge_webvpn网关共享课程时不能串课() {
    let transport = JudgeRepairTransport {
        scenario: Scenario::SharedCourses,
        ..Default::default()
    };
    let mut client = RouteClient::with_transport(
        ConnectionMode::WebVpn,
        transport,
        session_store_for(ConnectionMode::WebVpn, "judge-shared-course"),
    )
    .unwrap();
    let data = client.judge_assignments(false).await.unwrap().data;
    let mut actual: Vec<_> = data
        .iter()
        .map(|item| (item.course_id.as_str(), item.assignment_id.as_str()))
        .collect();
    actual.sort_unstable();
    assert_eq!(actual, vec![("1", "101"), ("2", "201")]);
    let keys = vec![
        JudgeAssignmentKey {
            course_id: "2".into(),
            assignment_id: "201".into(),
        },
        JudgeAssignmentKey {
            course_id: "1".into(),
            assignment_id: "101".into(),
        },
    ];
    let details = client.judge_assignment_details(&keys).await.unwrap().data;
    for (detail, key) in details.iter().zip(&keys) {
        assert_eq!(
            (&detail.course_id, &detail.assignment_id),
            (&key.course_id, &key.assignment_id)
        );
    }
}

#[tokio::test]
async fn judge_历史作业不截断后续近期作业也不排除刷新课程() {
    let transport = JudgeRepairTransport {
        scenario: Scenario::MixedHistory,
        ..Default::default()
    };
    let mut client = RouteClient::with_transport(
        ConnectionMode::Direct,
        transport,
        session_store_for(ConnectionMode::Direct, "judge-mixed-history"),
    )
    .unwrap();
    for _ in 0..2 {
        let data = client.judge_assignments(false).await.unwrap().data;
        let mut ids = data
            .iter()
            .map(|item| item.assignment_id.as_str())
            .collect::<Vec<_>>();
        ids.sort_unstable();
        assert_eq!(ids, vec!["101", "103"]);
    }
}

#[tokio::test]
async fn judge_详情重新认证后恢复目标课程() {
    for mode in [ConnectionMode::Direct, ConnectionMode::WebVpn] {
        let transport = JudgeRepairTransport {
            scenario: Scenario::ExpireDetail,
            ..Default::default()
        };
        let mut client =
            RouteClient::with_transport(mode, transport, session_store_for(mode, "judge-reselect"))
                .unwrap();
        assert_eq!(client.judge_assignments(false).await.unwrap().data.len(), 1);
    }
}
