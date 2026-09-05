use async_trait::async_trait;
use clap::Parser;
use std::io::Cursor;

use ubaa_cli::{
    CLI_JSON_SCHEMA_VERSION, Cli, CliBackend, RoutedCliBackend, run_with_backend,
    run_with_routed_backend,
};
use ubaa_core::facade::{
    ActionEligibility, AuthStatus, ConnectionMode, ErrorCode, ErrorKind, EvaluationBatchResult,
    EvaluationCourse, EvaluationCourseOutcome, EvaluationCourseResult, EvaluationCoursesResponse,
    EvaluationProgress, EvaluationSubmitCoursesRequest, EvaluationSubmitTarget, FeatureResult,
    LoginInput, NetworkState, Result, RouteDiagnostic, RoutePolicy, RouteResolution, Routed,
    RoutedResult, UbaaError, UserProfile,
};

use crate::common::assert_cli_schema;

#[derive(Clone, Copy, Default)]
enum BatchFixture {
    #[default]
    Success,
    Partial,
    OutcomeUnknown,
}

#[derive(Default)]
struct EvaluationBackend {
    courses: Vec<EvaluationCourse>,
    batch: BatchFixture,
    route: Option<ConnectionMode>,
    read_calls: usize,
    submit_calls: usize,
    readback_calls: usize,
    readback_routes: Vec<ConnectionMode>,
    submitted: Option<EvaluationSubmitCoursesRequest>,
    expected_submit_route: Option<ConnectionMode>,
    readback_fails: bool,
    commit_auth_fails: bool,
}

#[async_trait]
impl RoutedCliBackend for EvaluationBackend {
    async fn evaluation_all(&mut self) -> RoutedResult<EvaluationCoursesResponse> {
        self.read_calls += 1;
        Ok(Routed {
            data: response(self.courses.clone()),
            resolution: resolution(self.route.unwrap_or(ConnectionMode::Direct)),
        })
    }

    async fn evaluation_submit_courses_if_route_matches(
        &mut self,
        request: EvaluationSubmitCoursesRequest,
        expected_route: ConnectionMode,
    ) -> RoutedResult<EvaluationBatchResult> {
        self.submit_calls += 1;
        self.submitted = Some(request.clone());
        self.expected_submit_route = Some(expected_route);
        if self.commit_auth_fails {
            return Err(ubaa_core::facade::RoutedError {
                error: authentication_required(),
                resolution: Some(resolution(expected_route)),
            });
        }
        Ok(Routed {
            data: batch(self.batch, &request.targets),
            resolution: resolution(expected_route),
        })
    }

    async fn evaluation_all_on_route(
        &mut self,
        route: ConnectionMode,
    ) -> Result<EvaluationCoursesResponse> {
        self.readback_calls += 1;
        self.readback_routes.push(route);
        if self.readback_fails {
            Err(UbaaError::new(
                ErrorCode::UpstreamUnavailable,
                ErrorKind::Upstream,
                false,
                "fixture readback unavailable",
            ))
        } else {
            Ok(response(self.courses.clone()))
        }
    }
}

#[derive(Default)]
struct FixedEvaluationBackend {
    courses: Vec<EvaluationCourse>,
    submit_calls: usize,
    readback_calls: usize,
    submitted: Option<EvaluationSubmitCoursesRequest>,
    commit_auth_fails: bool,
}

#[async_trait]
impl CliBackend for FixedEvaluationBackend {
    fn mode(&self) -> ConnectionMode {
        ConnectionMode::Direct
    }

    async fn login(&mut self, _input: LoginInput) -> Result<UserProfile> {
        unreachable!("本测试不执行登录")
    }

    async fn auth_status(&mut self) -> Result<AuthStatus> {
        unreachable!("本测试不查询认证状态")
    }

    async fn get_user_info(&mut self) -> Result<UserProfile> {
        unreachable!("本测试不查询用户资料")
    }

    async fn logout(&mut self) -> Result<()> {
        unreachable!("本测试不执行登出")
    }

    async fn evaluation_all(&mut self) -> Result<FeatureResult<EvaluationCoursesResponse>> {
        Ok(FeatureResult {
            data: response(self.courses.clone()),
            resolved_route: ConnectionMode::Direct,
        })
    }

    async fn evaluation_submit_courses(
        &mut self,
        request: EvaluationSubmitCoursesRequest,
    ) -> Result<FeatureResult<EvaluationBatchResult>> {
        self.submit_calls += 1;
        self.submitted = Some(request.clone());
        if self.commit_auth_fails {
            return Err(authentication_required());
        }
        Ok(FeatureResult {
            data: batch(BatchFixture::Success, &request.targets),
            resolved_route: ConnectionMode::Direct,
        })
    }

    async fn evaluation_all_on_route(
        &mut self,
        route: ConnectionMode,
    ) -> Result<EvaluationCoursesResponse> {
        assert_eq!(route, ConnectionMode::Direct);
        self.readback_calls += 1;
        Ok(response(self.courses.clone()))
    }
}

#[test]
fn 评教仅保留_typed_submit_pending_且删除_raw_payload_入口() {
    let error = Cli::try_parse_from([
        "ubaa",
        "evaluation",
        "submit",
        "--payload",
        "/tmp/forbidden.json",
        "--confirm-write",
    ])
    .unwrap_err();

    assert!(
        error
            .to_string()
            .contains("unrecognized subcommand 'submit'")
    );
    Cli::try_parse_from(["ubaa", "evaluation", "submit-pending", "--confirm-write"]).unwrap();
}

#[tokio::test]
async fn 自动评教未确认时零读取零提交零回读() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "evaluation", "submit-pending"]).unwrap();
    let mut backend = EvaluationBackend::default();

    let (exit, value, stderr) = run_json(cli, &mut backend).await;

    assert_eq!(exit, 2);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "invalid_input");
    assert_eq!(backend.read_calls, 0);
    assert_eq!(backend.submit_calls, 0);
    assert_eq!(backend.readback_calls, 0);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn fresh_pending_为空时固定拒绝且零提交零回读() {
    let cli = submit_pending_cli();
    let mut backend = EvaluationBackend::default();

    let (exit, value, stderr) = run_json(cli, &mut backend).await;

    assert_eq!(exit, 2);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "invalid_input");
    assert_eq!(value["error"]["message"], "没有可提交的待评课程");
    assert_eq!(backend.read_calls, 1);
    assert_eq!(backend.submit_calls, 0);
    assert_eq!(backend.readback_calls, 0);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn pending_含未知缺失目标或规范化重复时整批拒绝() {
    let valid = pending_course("one", ActionEligibility::Allowed, Some(target("one", None)));
    let cases = [
        vec![
            valid.clone(),
            pending_course("unknown", ActionEligibility::Unknown, None),
        ],
        vec![
            valid.clone(),
            pending_course(
                "malformed",
                ActionEligibility::Allowed,
                Some(EvaluationSubmitTarget {
                    rwid: " ".into(),
                    ..target("malformed", None)
                }),
            ),
        ],
        vec![
            pending_course(
                "same-a",
                ActionEligibility::Allowed,
                Some(target("same", None)),
            ),
            pending_course(
                "same-b",
                ActionEligibility::Allowed,
                Some(target("same", Some(""))),
            ),
        ],
    ];

    for courses in cases {
        let mut backend = EvaluationBackend {
            courses,
            ..EvaluationBackend::default()
        };

        let (exit, value, stderr) = run_json(submit_pending_cli(), &mut backend).await;

        assert_eq!(exit, 6);
        assert_cli_schema(&value);
        assert_eq!(value["error"]["code"], "upstream_changed");
        assert_eq!(backend.read_calls, 1);
        assert_eq!(backend.submit_calls, 0);
        assert_eq!(backend.readback_calls, 0);
        assert!(stderr.is_empty());
    }
}

#[tokio::test]
async fn allowed_目标按原顺序固定路线提交并在确定结果后回读一次() {
    let route = ConnectionMode::WebVpn;
    let mut backend = EvaluationBackend {
        courses: vec![
            evaluated_course("done"),
            pending_course(
                "first",
                ActionEligibility::Allowed,
                Some(target("first", None)),
            ),
            pending_course(
                "second",
                ActionEligibility::Allowed,
                Some(target("second", Some("group"))),
            ),
        ],
        batch: BatchFixture::Partial,
        route: Some(route),
        readback_fails: true,
        ..EvaluationBackend::default()
    };

    let (exit, value, stderr) = run_json(submit_pending_cli(), &mut backend).await;

    assert_eq!(exit, 0, "确定性部分失败仍是已知业务结果");
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 10);
    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["success"], false);
    assert_eq!(value["data"]["outcomeUnknown"], false);
    assert_eq!(value["data"]["items"][0]["target"]["kcdm"], "first-kcdm");
    assert_eq!(value["data"]["items"][1]["outcome"], "failure");
    assert_eq!(backend.submit_calls, 1);
    assert_eq!(backend.expected_submit_route, Some(route));
    assert_eq!(backend.readback_routes, vec![route]);
    let submitted = backend.submitted.unwrap();
    assert_eq!(submitted.targets.len(), 2);
    assert_eq!(submitted.targets[0].kcdm, "first-kcdm");
    assert_eq!(submitted.targets[1].kcdm, "second-kcdm");
    assert_eq!(submitted.targets[1].bpdm.as_deref(), Some("group"));
    assert!(stderr.is_empty(), "best-effort 回读失败不得覆盖 batch");
}

#[tokio::test]
async fn 单路线后端同样使用_typed_目标并在原路线回读一次() {
    let mut backend = FixedEvaluationBackend {
        courses: vec![pending_course(
            "fixed",
            ActionEligibility::Allowed,
            Some(target("fixed", None)),
        )],
        ..FixedEvaluationBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_backend(
        submit_pending_cli(),
        &mut backend,
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["data"]["success"], true);
    assert_eq!(backend.submit_calls, 1);
    assert_eq!(backend.readback_calls, 1);
    assert_eq!(backend.submitted.unwrap().targets[0].kcdm, "fixed-kcdm");
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn commit_阶段错误保持主分类且只回读原路线不重提() {
    let route = ConnectionMode::WebVpn;
    let mut backend = EvaluationBackend {
        courses: vec![pending_course(
            "auth-failure",
            ActionEligibility::Allowed,
            Some(target("auth-failure", None)),
        )],
        route: Some(route),
        readback_fails: true,
        commit_auth_fails: true,
        ..EvaluationBackend::default()
    };

    let (exit, value, stderr) = run_json(submit_pending_cli(), &mut backend).await;

    assert_eq!(exit, 3);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "authentication_required");
    assert_eq!(backend.submit_calls, 1, "commit 错误后不得自动重提");
    assert_eq!(backend.readback_calls, 1);
    assert_eq!(backend.readback_routes, vec![route]);
    assert!(stderr.is_empty(), "best-effort 回读错误不得覆盖主错误");
}

#[tokio::test]
async fn 单路线_commit_错误同样回读一次且保持主错误() {
    let mut backend = FixedEvaluationBackend {
        courses: vec![pending_course(
            "fixed-auth-failure",
            ActionEligibility::Allowed,
            Some(target("fixed-auth-failure", None)),
        )],
        commit_auth_fails: true,
        ..FixedEvaluationBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();

    let exit = run_with_backend(
        submit_pending_cli(),
        &mut backend,
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;
    let value: serde_json::Value = serde_json::from_slice(&stdout).unwrap();

    assert_eq!(exit, 3);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "authentication_required");
    assert_eq!(backend.submit_calls, 1);
    assert_eq!(backend.readback_calls, 1);
    assert!(stderr.is_empty());
}

#[tokio::test]
async fn outcome_unknown_使用唯一带安全_batch_数据的失败信封并固定路线回读() {
    let route = ConnectionMode::WebVpn;
    let mut backend = EvaluationBackend {
        courses: vec![
            pending_course(
                "first",
                ActionEligibility::Allowed,
                Some(target("first", None)),
            ),
            pending_course(
                "second",
                ActionEligibility::Allowed,
                Some(target("second", None)),
            ),
        ],
        batch: BatchFixture::OutcomeUnknown,
        route: Some(route),
        ..EvaluationBackend::default()
    };

    let (exit, value, stderr) = run_json(submit_pending_cli(), &mut backend).await;

    assert_eq!(exit, 5);
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 10);
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "outcome_unknown");
    assert_eq!(value["data"]["outcomeUnknown"], true);
    assert_eq!(value["data"]["items"][0]["outcome"], "outcomeUnknown");
    assert_eq!(value["data"]["items"][1]["outcome"], "unattempted");
    assert_eq!(backend.submit_calls, 1);
    assert_eq!(backend.readback_routes, vec![route]);
    assert!(stderr.is_empty());
    for forbidden in ["cookie", "token", "payload", "question", "answer"] {
        assert!(!value.to_string().to_ascii_lowercase().contains(forbidden));
    }
}

#[tokio::test]
async fn 评教读取只输出安全课程投影且符合_schema_v10() {
    let cli = Cli::try_parse_from(["ubaa", "--json", "evaluation", "all"]).unwrap();
    let mut backend = EvaluationBackend {
        courses: vec![pending_course(
            "safe",
            ActionEligibility::Allowed,
            Some(target("safe", None)),
        )],
        ..EvaluationBackend::default()
    };

    let (exit, value, stderr) = run_json(cli, &mut backend).await;

    assert_eq!(exit, 0);
    assert_cli_schema(&value);
    assert_eq!(value["schemaVersion"], 10);
    let course = &value["data"]["courses"][0];
    assert_eq!(course["submitEligibility"], "allowed");
    assert_eq!(course["submitTarget"]["rwid"], "safe-rwid");
    for forbidden in [
        "msid",
        "pjrdm",
        "pjrmc",
        "xnxq",
        "zdmc",
        "ypjcs",
        "xypjcs",
        "sxz",
        "rwh",
        "pjlxid",
        "sfksqbpj",
        "yxsfktjst",
    ] {
        assert!(course.get(forbidden).is_none(), "泄漏内部字段 {forbidden}");
    }
    assert!(stderr.is_empty());
}

#[test]
fn cli_评教合同升级为唯一_schema_v10_且失败携带数据仅限未知_batch() {
    assert_eq!(CLI_JSON_SCHEMA_VERSION, 10);
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../docs/contracts/cli-json.schema.json"
    ))
    .unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();

    let unknown = unknown_envelope();
    assert!(validator.is_valid(&unknown));

    let mut old = unknown.clone();
    old["schemaVersion"] = 9.into();
    assert!(!validator.is_valid(&old));

    let mut wrong_feature = unknown.clone();
    wrong_feature["meta"]["feature"] = "signin".into();
    assert!(!validator.is_valid(&wrong_feature));

    let mut wrong_error = unknown.clone();
    wrong_error["error"]["code"] = "upstream_changed".into();
    assert!(!validator.is_valid(&wrong_error));

    let mut known_batch = unknown;
    known_batch["data"]["outcomeUnknown"] = false.into();
    assert!(!validator.is_valid(&known_batch));
}

async fn run_json(cli: Cli, backend: &mut EvaluationBackend) -> (i32, serde_json::Value, Vec<u8>) {
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let exit = run_with_routed_backend(cli, backend, &mut stdout, &mut stderr).await;
    let value = serde_json::from_slice(&stdout).unwrap();
    (exit, value, stderr)
}

fn submit_pending_cli() -> Cli {
    Cli::try_parse_from([
        "ubaa",
        "--json",
        "evaluation",
        "submit-pending",
        "--confirm-write",
    ])
    .unwrap()
}

fn target(label: &str, bpdm: Option<&str>) -> EvaluationSubmitTarget {
    EvaluationSubmitTarget {
        rwid: format!("{label}-rwid"),
        wjid: format!("{label}-wjid"),
        kcdm: format!("{label}-kcdm"),
        bpdm: bpdm.map(str::to_owned),
    }
}

fn pending_course(
    label: &str,
    submit_eligibility: ActionEligibility,
    submit_target: Option<EvaluationSubmitTarget>,
) -> EvaluationCourse {
    EvaluationCourse {
        id: format!("{label}-id"),
        kcmc: format!("脱敏课程-{label}"),
        bpmc: "脱敏教师".into(),
        is_evaluated: false,
        submit_eligibility,
        submit_target,
    }
}

fn evaluated_course(label: &str) -> EvaluationCourse {
    EvaluationCourse {
        is_evaluated: true,
        submit_eligibility: ActionEligibility::Denied,
        submit_target: None,
        ..pending_course(label, ActionEligibility::Denied, None)
    }
}

fn response(courses: Vec<EvaluationCourse>) -> EvaluationCoursesResponse {
    let total_courses = i32::try_from(courses.len()).unwrap();
    let evaluated_courses =
        i32::try_from(courses.iter().filter(|course| course.is_evaluated).count()).unwrap();
    EvaluationCoursesResponse {
        courses,
        progress: EvaluationProgress {
            total_courses,
            evaluated_courses,
            pending_courses: total_courses - evaluated_courses,
        },
    }
}

fn batch(fixture: BatchFixture, targets: &[EvaluationSubmitTarget]) -> EvaluationBatchResult {
    let items = targets
        .iter()
        .enumerate()
        .map(|(index, target)| {
            let outcome = match fixture {
                BatchFixture::Success => EvaluationCourseOutcome::Success,
                BatchFixture::Partial if index == 0 => EvaluationCourseOutcome::Success,
                BatchFixture::Partial => EvaluationCourseOutcome::Failure,
                BatchFixture::OutcomeUnknown if index == 0 => {
                    EvaluationCourseOutcome::OutcomeUnknown
                }
                BatchFixture::OutcomeUnknown => EvaluationCourseOutcome::Unattempted,
            };
            EvaluationCourseResult {
                target: target.clone(),
                course_name: format!("脱敏课程-{index}"),
                outcome,
                message: match outcome {
                    EvaluationCourseOutcome::Success => "评教已提交",
                    EvaluationCourseOutcome::Failure => "评教未提交，请刷新课程后重试",
                    EvaluationCourseOutcome::OutcomeUnknown => "评教提交结果未知，请刷新课程后核对",
                    EvaluationCourseOutcome::Unattempted => "前序课程结果未知，本课程未尝试",
                }
                .into(),
            }
        })
        .collect();
    EvaluationBatchResult {
        items,
        success: matches!(fixture, BatchFixture::Success),
        outcome_unknown: matches!(fixture, BatchFixture::OutcomeUnknown),
    }
}

fn resolution(route: ConnectionMode) -> RouteResolution {
    RouteResolution {
        mode: route,
        policy: match route {
            ConnectionMode::Direct => RoutePolicy::Direct,
            ConnectionMode::WebVpn => RoutePolicy::WebVpn,
        },
        diagnostic: RouteDiagnostic::new(NetworkState::Unknown, route),
    }
}

fn authentication_required() -> UbaaError {
    UbaaError::new(
        ErrorCode::AuthenticationRequired,
        ErrorKind::Authentication,
        false,
        "评教会话已失效",
    )
}

fn unknown_envelope() -> serde_json::Value {
    serde_json::json!({
        "schemaVersion": 10,
        "ok": false,
        "data": {
            "items": [{
                "target": {"rwid": "r", "wjid": "w", "kcdm": "k", "bpdm": null},
                "courseName": "脱敏课程",
                "outcome": "outcomeUnknown",
                "message": "评教提交结果未知，请刷新课程后核对"
            }],
            "success": false,
            "outcomeUnknown": true
        },
        "error": {
            "code": "outcome_unknown",
            "kind": "upstream",
            "message": "评教批量提交结果未知，请刷新课程核对后再操作",
            "retryable": false
        },
        "meta": {
            "routePolicy": "direct",
            "networkState": "unknown",
            "initialRoute": "direct",
            "resolvedRoute": "direct",
            "usedFallback": false,
            "feature": "evaluation"
        }
    })
}
