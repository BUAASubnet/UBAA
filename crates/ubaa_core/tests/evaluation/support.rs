use std::collections::HashSet;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use serde_json::{Value, json};
use ubaa_core::facade::testing::{
    FileSessionStore, HttpRequest, HttpResponse, HttpTransport, SessionSnapshot, SessionStore,
};
use ubaa_core::facade::{
    ConnectionMode, ErrorCode, ErrorKind, EvaluationSubmitTarget, Result, RouteClient, UbaaError,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum ReviseReply {
    Success,
    NonAuthenticationFailure,
    AuthenticationFailure,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum FinalReply {
    Success,
    Failure,
    Ambiguous,
    TransportFailure,
}

#[derive(Clone, Debug)]
pub(super) struct Scenario {
    pub(super) course_rounds: Vec<Vec<Value>>,
    pub(super) task_repetitions: usize,
    pub(super) form_repetitions: usize,
    pub(super) revise_replies: Vec<ReviseReply>,
    pub(super) topic_failures: HashSet<String>,
    pub(super) final_replies: Vec<FinalReply>,
}

impl Scenario {
    pub(super) fn one_course() -> Self {
        Self {
            course_rounds: vec![vec![course_row("course-1", Some("teacher-1"), &json!(0))]],
            task_repetitions: 1,
            form_repetitions: 1,
            revise_replies: vec![ReviseReply::Success],
            topic_failures: HashSet::new(),
            final_replies: vec![FinalReply::Success],
        }
    }
}

#[derive(Clone)]
pub(super) struct EvaluationMock {
    state: Arc<Mutex<State>>,
}

#[derive(Debug)]
struct State {
    scenario: Scenario,
    requests: Vec<HttpRequest>,
    authority_round: usize,
    revise_index: usize,
    final_index: usize,
}

impl EvaluationMock {
    pub(super) fn new(scenario: Scenario) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                scenario,
                requests: Vec::new(),
                authority_round: 0,
                revise_index: 0,
                final_index: 0,
            })),
        }
    }

    pub(super) fn requests(&self) -> Vec<HttpRequest> {
        self.state.lock().unwrap().requests.clone()
    }
}

#[async_trait]
impl HttpTransport for EvaluationMock {
    async fn execute(&self, request: HttpRequest) -> Result<HttpResponse> {
        let url = url::Url::parse(&request.url).expect("合成评教 URL");
        let path = url.path().to_owned();
        let mut state = self.state.lock().unwrap();
        state.requests.push(request.clone());
        let response = match path.as_str() {
            "/pjxt/cas" => response(&request, 200, ""),
            "/pjxt/personnelEvaluation/listObtainPersonnelEvaluationTasks" => {
                state.authority_round = state.authority_round.saturating_add(1);
                let rows = (0..state.scenario.task_repetitions)
                    .map(|_| json!({"rwid":"task-1","rwmc":"评教任务"}))
                    .collect::<Vec<_>>();
                response(
                    &request,
                    200,
                    &json!({"code":200,"result":{"list":rows}}).to_string(),
                )
            }
            "/pjxt/evaluationMethodSix/getQuestionnaireListToTask" => {
                let rows = (0..state.scenario.form_repetitions)
                    .map(|_| json!({"wjid":"form-1","wjmc":"问卷","msid":"mode-1"}))
                    .collect::<Vec<_>>();
                response(
                    &request,
                    200,
                    &json!({"code":200,"result":rows}).to_string(),
                )
            }
            "/pjxt/evaluationMethodSix/getRequiredReviewsData" => {
                let round = state.authority_round.saturating_sub(1);
                let courses = state
                    .scenario
                    .course_rounds
                    .get(round)
                    .or_else(|| state.scenario.course_rounds.last())
                    .cloned()
                    .unwrap_or_default();
                response(
                    &request,
                    200,
                    &json!({"code":200,"result":courses}).to_string(),
                )
            }
            "/pjxt/evaluationMethodSix/reviseQuestionnairePattern" => {
                let reply = state
                    .scenario
                    .revise_replies
                    .get(state.revise_index)
                    .copied()
                    .unwrap_or(ReviseReply::Success);
                state.revise_index += 1;
                match reply {
                    ReviseReply::Success => response(&request, 200, r#"{"code":200}"#),
                    ReviseReply::NonAuthenticationFailure => {
                        response(&request, 500, r#"{"code":500}"#)
                    }
                    ReviseReply::AuthenticationFailure => {
                        response(&request, 401, "authentication required")
                    }
                }
            }
            "/pjxt/evaluationMethodSix/getQuestionnaireTopic" => {
                let query = query_value(&url, "kcdm");
                if state.scenario.topic_failures.contains(&query) {
                    response(&request, 200, r#"{"code":200,"result":[]}"#)
                } else {
                    response(
                        &request,
                        200,
                        &json!({"code":200,"result":[topic(&url)]}).to_string(),
                    )
                }
            }
            "/pjxt/evaluationMethodSix/submitSaveEvaluation" => {
                let reply = state
                    .scenario
                    .final_replies
                    .get(state.final_index)
                    .copied()
                    .unwrap_or(FinalReply::Success);
                state.final_index += 1;
                match reply {
                    FinalReply::Success => response(&request, 200, r#"{"code":200}"#),
                    FinalReply::Failure => response(&request, 200, r#"{"code":500}"#),
                    FinalReply::Ambiguous => response(&request, 200, r#"{"message":"unknown"}"#),
                    FinalReply::TransportFailure => {
                        return Err(UbaaError::new(
                            ErrorCode::Timeout,
                            ErrorKind::Network,
                            true,
                            "合成 final timeout",
                        ));
                    }
                }
            }
            _ => panic!("未预期的评教请求路径：{path}"),
        };
        Ok(response)
    }
}

pub(super) fn course_row(kcdm: &str, bpdm: Option<&str>, ypjcs: &Value) -> Value {
    json!({
        "kcdm": kcdm,
        "bpdm": bpdm,
        "kcmc": format!("课程 {kcdm}"),
        "bpmc": format!("教师 {kcdm}"),
        "ypjcs": ypjcs,
        "xypjcs": 1,
        "sxz": "student-kind",
        "pjrdm": "reviewer-1",
        "pjrmc": "评价人",
        "rwh": format!("row-{kcdm}"),
        "xn": "2026",
        "xq": "1",
        "xnxq": "2026-2027-1",
        "yxsfktjst": "0"
    })
}

pub(super) fn target(kcdm: &str, bpdm: Option<&str>) -> EvaluationSubmitTarget {
    EvaluationSubmitTarget {
        rwid: "task-1".into(),
        wjid: "form-1".into(),
        kcdm: kcdm.into(),
        bpdm: bpdm.map(str::to_owned),
    }
}

pub(super) fn route_client(
    label: &str,
    transport: EvaluationMock,
) -> (RouteClient, std::path::PathBuf) {
    let root = super::test_root(label);
    let _ = std::fs::remove_dir_all(&root);
    let store = FileSessionStore::new(&root).unwrap();
    store
        .save(&SessionSnapshot {
            mode: ConnectionMode::Direct,
            cookies: Vec::new(),
            authenticated_at: 1_000,
            last_activity: 1_001,
        })
        .unwrap();
    (
        RouteClient::with_transport(ConnectionMode::Direct, transport, store).unwrap(),
        root,
    )
}

pub(super) fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap()
}

fn response(request: &HttpRequest, status: u16, body: &str) -> HttpResponse {
    HttpResponse::new(status, request.url.clone(), body.as_bytes().to_vec())
}

fn topic(url: &url::Url) -> Value {
    let kcdm = query_value(url, "kcdm");
    json!({
        "pjmap": {"source":"fixture"},
        "pjxtWjWjbReturnEntity": {"wjzblist":[{"tklist":[
            {"tmlx":"1","tmid":format!("question-{kcdm}"),"tmxxlist":[
                {"tmxxid":"option-a"},{"tmxxid":"option-b"}
            ]},
            {"tmlx":"6","tmid":format!("subjective-{kcdm}"),"tmxxlist":[
                {"tmxxid":"subjective-option"}
            ]}
        ]}]},
        "pjxtPjjgPjjgckb":[{
            "wjssrwid":format!("assignment-{kcdm}"),
            "bprdm":query_value(url,"bpdm"),
            "bprmc":query_value(url,"bpmc"),
            "kcdm":kcdm,
            "kcmc":query_value(url,"kcmc"),
            "pjfs":"1",
            "pjid":format!("evaluation-{}",query_value(url,"kcdm")),
            "pjlx":"2",
            "pjrdm":query_value(url,"pjrdm"),
            "pjrjsdm":"student-role-1",
            "pjrxm":query_value(url,"pjrmc"),
            "xnxq":query_value(url,"xnxq"),
            "sfxxpj":"1"
        }]
    })
}

fn query_value(url: &url::Url, key: &str) -> String {
    url.query_pairs()
        .find_map(|(candidate, value)| (candidate == key).then(|| value.into_owned()))
        .unwrap_or_default()
}
