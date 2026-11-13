#[test]
fn 评教仅保留_typed_submit_pending_且删除_raw_payload_入口() {
    let error = Cli::try_parse_from([
        "ubaa-cli",
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
    Cli::try_parse_from(["ubaa-cli", "evaluation", "submit-pending", "--confirm-write"]).unwrap();
}

#[tokio::test]
async fn 自动评教未确认时零读取零提交零回读() {
    let cli = Cli::try_parse_from(["ubaa-cli", "--json", "evaluation", "submit-pending"]).unwrap();
    let mut backend = EvaluationBackend::default();

    let (exit, value, stderr) = run_json(cli, &mut backend).await;

    assert_eq!(exit, 2);
    assert_cli_schema(&value);
    assert_eq!(value["error"]["code"], "invalid_input");
    assert_eq!(backend.read_calls, 0);
    assert_eq!(backend.submit_calls, 0);
    assert_eq!(backend.readback_calls, 0);
    assert_eq!(stderr.len(), 0);
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
    assert_eq!(stderr.len(), 0);
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
        assert_eq!(stderr.len(), 0);
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
    assert_eq!(value["schemaVersion"], 16);
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
    assert_eq!(stderr.len(), 0);
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
    assert_eq!(stderr.len(), 0);
}

#[tokio::test]
async fn outcome_unknown_使用带安全_batch_数据的失败信封并固定路线回读() {
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
    assert_eq!(value["schemaVersion"], 16);
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "outcome_unknown");
    assert_eq!(value["data"]["outcomeUnknown"], true);
    assert_eq!(value["data"]["items"][0]["outcome"], "outcomeUnknown");
    assert_eq!(value["data"]["items"][1]["outcome"], "unattempted");
    assert_eq!(backend.submit_calls, 1);
    assert_eq!(backend.readback_routes, vec![route]);
    assert_eq!(stderr.len(), 0);
    for forbidden in ["cookie", "token", "payload", "question", "answer"] {
        assert!(!value.to_string().to_ascii_lowercase().contains(forbidden));
    }
}

#[tokio::test]
async fn 更新门控中止评教后续提交时保留已知结果并退出8() {
    fn assert_gated_batch(exit: i32, value: &serde_json::Value, stderr: &[u8]) {
        assert_eq!(exit, 8);
        assert_cli_schema(value);
        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "update_required");
        assert_eq!(value["error"]["retryable"], false);
        assert_eq!(value["data"]["outcomeUnknown"], false);
        assert_eq!(value["data"]["success"], false);
        assert_eq!(value["data"]["items"][0]["outcome"], "success");
        assert_eq!(value["data"]["items"][1]["outcome"], "failure");
        assert_eq!(value["data"]["items"][2]["outcome"], "unattempted");
        assert_eq!(stderr.len(), 0);
    }

    let courses: Vec<_> = ["first", "second", "third"]
        .into_iter()
        .map(|id| pending_course(id, ActionEligibility::Allowed, Some(target(id, None))))
        .collect();
    let route = ConnectionMode::WebVpn;
    let mut routed = EvaluationBackend {
        courses: courses.clone(),
        batch: BatchFixture::UpdateRequired,
        route: Some(route),
        ..EvaluationBackend::default()
    };
    let (exit, value, stderr) = run_json(submit_pending_cli(), &mut routed).await;
    assert_gated_batch(exit, &value, &stderr);
    assert_eq!(routed.submit_calls, 1);
    assert_eq!(routed.readback_routes, vec![route]);

    let mut fixed = FixedEvaluationBackend {
        courses,
        batch: BatchFixture::UpdateRequired,
        ..FixedEvaluationBackend::default()
    };
    let mut stdout = Vec::new();
    let mut stderr = Vec::new();
    let exit = run_with_backend(
        submit_pending_cli(),
        &mut fixed,
        &mut Cursor::new(Vec::<u8>::new()),
        &mut stdout,
        &mut stderr,
    )
    .await;
    assert_gated_batch(exit, &serde_json::from_slice(&stdout).unwrap(), &stderr);
    assert_eq!(fixed.submit_calls, 1);
    assert_eq!(fixed.readback_calls, 1);
}

#[tokio::test]
async fn 评教读取只输出安全课程投影且符合_schema_v10() {
    let cli = Cli::try_parse_from(["ubaa-cli", "--json", "evaluation", "all"]).unwrap();
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
    assert_eq!(value["schemaVersion"], 16);
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
    assert_eq!(stderr.len(), 0);
}

#[test]
fn cli_评教失败仅在结果未知或更新门控中止批次时携带数据() {
    assert_eq!(CLI_JSON_SCHEMA_VERSION, 16);
    let schema: serde_json::Value = serde_json::from_str(include_str!(
        "../../../../../docs/contracts/cli-json.schema.json"
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

    let mut gated_batch = known_batch;
    gated_batch["error"]["code"] = "update_required".into();
    let items = gated_batch["data"]["items"].as_array_mut().unwrap();
    items[0]["outcome"] = "success".into();
    let mut unattempted = items[0].clone();
    unattempted["outcome"] = "unattempted".into();
    items.push(unattempted);
    assert!(validator.is_valid(&gated_batch));

    let mut retryable = gated_batch.clone();
    retryable["error"]["retryable"] = true.into();
    assert!(!validator.is_valid(&retryable));

    let mut no_remaining = gated_batch.clone();
    no_remaining["data"]["items"][1]["outcome"] = "failure".into();
    assert!(!validator.is_valid(&no_remaining));

    let mut false_success = gated_batch;
    false_success["ok"] = true.into();
    false_success.as_object_mut().unwrap().remove("error");
    assert!(!validator.is_valid(&false_success));
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
        "ubaa-cli",
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
            let outcome = match (fixture, index) {
                (BatchFixture::Success, _) | (BatchFixture::Partial | BatchFixture::UpdateRequired, 0) => {
                    EvaluationCourseOutcome::Success
                }
                (BatchFixture::Partial, _) | (BatchFixture::UpdateRequired, 1) => EvaluationCourseOutcome::Failure,
                (BatchFixture::OutcomeUnknown, 0) => EvaluationCourseOutcome::OutcomeUnknown,
                (BatchFixture::OutcomeUnknown | BatchFixture::UpdateRequired, _) => EvaluationCourseOutcome::Unattempted,
            };
            EvaluationCourseResult {
                target: target.clone(),
                course_name: format!("脱敏课程-{index}"),
                outcome,
                message: match outcome {
                    EvaluationCourseOutcome::Success => "评教已提交",
                    EvaluationCourseOutcome::Failure => "评教未提交，请刷新课程后重试",
                    EvaluationCourseOutcome::OutcomeUnknown => "评教提交结果未知，请刷新课程后核对",
                    EvaluationCourseOutcome::Unattempted
                        if matches!(fixture, BatchFixture::UpdateRequired) =>
                    {
                        "请先更新客户端，本课程未尝试"
                    }
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
        "schemaVersion": 16,
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
