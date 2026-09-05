part of '../bridge_backend_test.dart';

void _registerEvaluationBridgeBackendTests() {
  test('BridgeBackend 评教读取只从 typed 资格与目标构造 action', () async {
    final client = _EvaluationBridgeClient(
      response: const BridgeEvaluationCoursesResponse(
        courses: <BridgeEvaluationCourse>[
          BridgeEvaluationCourse(
            id: 'task-1_questionnaire-1_COURSE-1_teacher-1',
            kcmc: '编译原理',
            bpmc: '测试教师',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'task-1',
              wjid: 'questionnaire-1',
              kcdm: 'COURSE-1',
              bpdm: 'teacher-1',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'completed-course',
            kcmc: '高等数学',
            bpmc: '另一位教师',
            isEvaluated: true,
            submitEligibility: BridgeActionEligibility.denied,
          ),
        ],
        progress: BridgeEvaluationProgress(
          totalCourses: 2,
          evaluatedCourses: 1,
          pendingCourses: 1,
        ),
      ),
    );
    final backend = BridgeBackend(client);

    final result = await backend.loadFeatureQuery(
      FeatureId.evaluation,
      const FeatureQuery(),
    );
    final action = result.details.first.action<EvaluationSubmitAction>();

    expect(result.summary, '已评 1/2 门');
    expect(result.resolvedRoute, ConnectionMode.webvpn);
    expect(result.details.first.title, '编译原理');
    expect(result.details.first.subtitle, '测试教师');
    expect(action?.eligibility, ActionEligibility.allowed);
    expect(action?.hasCanonicalTarget, isTrue);
    expect(
      <String?>[
        action?.target?.rwid,
        action?.target?.wjid,
        action?.target?.kcdm,
        action?.target?.bpdm,
      ],
      <String?>['task-1', 'questionnaire-1', 'COURSE-1', 'teacher-1'],
    );
    final completed = result.details.last.action<EvaluationSubmitAction>();
    expect(completed?.eligibility, ActionEligibility.denied);
    expect(completed?.target, isNull);
  });

  test('BridgeBackend 评教固定路线回读不执行 Auto 且保留原路线', () async {
    final client = _EvaluationBridgeClient(
      response: const BridgeEvaluationCoursesResponse(
        courses: <BridgeEvaluationCourse>[
          BridgeEvaluationCourse(
            id: 'task-read_questionnaire-read_READ1_',
            kcmc: '回读课程',
            bpmc: '回读教师',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'task-read',
              wjid: 'questionnaire-read',
              kcdm: 'READ1',
            ),
          ),
        ],
        progress: BridgeEvaluationProgress(
          totalCourses: 1,
          evaluatedCourses: 0,
          pendingCourses: 1,
        ),
      ),
    );
    final backend = BridgeBackend(client);

    final result = await backend.loadEvaluationOnRoute(
      route: ConnectionMode.direct,
    );

    expect(client.evaluationAllCalls, 0);
    expect(client.pinnedRoutes, const <BridgeConnectionMode>[
      BridgeConnectionMode.direct,
    ]);
    expect(result.resolvedRoute, ConnectionMode.direct);
    expect(
      result.details.single
          .action<EvaluationSubmitAction>()
          ?.target
          ?.selectionKey,
      '9:task-read|18:questionnaire-read|5:READ1|0:',
    );
  });

  test('BridgeBackend 评教重复空白与不一致 typed 数据逐项 fail-closed', () async {
    final client = _EvaluationBridgeClient(
      response: const BridgeEvaluationCoursesResponse(
        courses: <BridgeEvaluationCourse>[
          BridgeEvaluationCourse(
            id: 'duplicate-task_duplicate-form_DUP_teacher',
            kcmc: '重复一',
            bpmc: '教师一',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'duplicate-task',
              wjid: 'duplicate-form',
              kcdm: 'DUP',
              bpdm: 'teacher',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'duplicate-task_duplicate-form_DUP_teacher',
            kcmc: '重复二',
            bpmc: '教师二',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'duplicate-task',
              wjid: 'duplicate-form',
              kcdm: 'DUP',
              bpdm: 'teacher',
            ),
          ),
          BridgeEvaluationCourse(
            id: ' spaced-task_spaced-form_SPACE_',
            kcmc: '空白目标',
            bpmc: '教师三',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: ' spaced-task',
              wjid: 'spaced-form',
              kcdm: 'SPACE',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'spaced-task_spaced-form_SPACE_',
            kcmc: '空白归一化别名',
            bpmc: '教师四',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'spaced-task',
              wjid: 'spaced-form',
              kcdm: 'SPACE',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'alias-task_alias-form_ALIAS_',
            kcmc: '空教师代码',
            bpmc: '教师五',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'alias-task',
              wjid: 'alias-form',
              kcdm: 'ALIAS',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'alias-task_alias-form_ALIAS_',
            kcmc: '空字符串教师代码别名',
            bpmc: '教师六',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'alias-task',
              wjid: 'alias-form',
              kcdm: 'ALIAS',
              bpdm: '',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'wrong-id',
            kcmc: '标识不一致',
            bpmc: '教师七',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'id-task',
              wjid: 'id-form',
              kcdm: 'ID1',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'done-task_done-form_DONE_',
            kcmc: '已评却允许',
            bpmc: '教师八',
            isEvaluated: true,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'done-task',
              wjid: 'done-form',
              kcdm: 'DONE',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'name-task_name-form_NAME_',
            kcmc: '   ',
            bpmc: '教师九',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'name-task',
              wjid: 'name-form',
              kcdm: 'NAME',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'teacher-task_teacher-form_TEACHER_',
            kcmc: '教师名为空',
            bpmc: '   ',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'teacher-task',
              wjid: 'teacher-form',
              kcdm: 'TEACHER',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'missing-target',
            kcmc: '允许但缺目标',
            bpmc: '教师十',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
          ),
          BridgeEvaluationCourse(
            id: 'denied-task_denied-form_DENIED_',
            kcmc: '拒绝却夹带目标',
            bpmc: '教师十一',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.denied,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'denied-task',
              wjid: 'denied-form',
              kcdm: 'DENIED',
            ),
          ),
          BridgeEvaluationCourse(
            id: 'denied-clean',
            kcmc: '明确拒绝',
            bpmc: '教师十二',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.denied,
          ),
          BridgeEvaluationCourse(
            id: 'unknown-clean',
            kcmc: '资格未知',
            bpmc: '教师十三',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.unknown,
          ),
          BridgeEvaluationCourse(
            id: 'valid-task_valid-form_VALID_',
            kcmc: '唯一有效课程',
            bpmc: '有效教师',
            isEvaluated: false,
            submitEligibility: BridgeActionEligibility.allowed,
            submitTarget: BridgeEvaluationSubmitTarget(
              rwid: 'valid-task',
              wjid: 'valid-form',
              kcdm: 'VALID',
            ),
          ),
        ],
        progress: BridgeEvaluationProgress(
          totalCourses: 15,
          evaluatedCourses: 1,
          pendingCourses: 14,
        ),
      ),
    );

    final result = await BridgeBackend(
      client,
    ).loadFeatureQuery(FeatureId.evaluation, const FeatureQuery());
    final actions = result.details
        .map((detail) => detail.action<EvaluationSubmitAction>()!)
        .toList(growable: false);

    expect(actions.map((action) => action.eligibility), <ActionEligibility>[
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.unknown,
      ActionEligibility.denied,
      ActionEligibility.unknown,
      ActionEligibility.allowed,
    ]);
    expect(actions.where((action) => action.target != null), hasLength(1));
    expect(actions.last.target?.rwid, 'valid-task');
    expect(result.details[8].title, '未知课程');
    expect(result.details[9].subtitle, '未知教师');
  });

  test('BridgeBackend 评教 prepare 只按顺序传递 typed targets', () async {
    final client = _EvaluationBridgeClient(
      response: const BridgeEvaluationCoursesResponse(
        courses: <BridgeEvaluationCourse>[],
        progress: BridgeEvaluationProgress(
          totalCourses: 0,
          evaluatedCourses: 0,
          pendingCourses: 0,
        ),
      ),
    );
    final backend = BridgeBackend(client);

    final intent = await backend
        .prepareEvaluationSubmitCourses(const <EvaluationSubmitTarget>[
          EvaluationSubmitTarget(
            rwid: 'task-1',
            wjid: 'form-1',
            kcdm: 'COURSE-1',
            bpdm: 'teacher-1',
          ),
          EvaluationSubmitTarget(
            rwid: 'task-2',
            wjid: 'form-2',
            kcdm: 'COURSE-2',
          ),
        ]);

    expect(intent.operation, WriteOperation.evaluationSubmitCourses);
    expect(client.prepareCalls, 1);
    expect(
      client.prepareRequest?.targets
          .map(
            (target) => <String?>[
              target.rwid,
              target.wjid,
              target.kcdm,
              target.bpdm,
            ],
          )
          .toList(growable: false),
      <List<String?>>[
        <String?>['task-1', 'form-1', 'COURSE-1', 'teacher-1'],
        <String?>['task-2', 'form-2', 'COURSE-2', null],
      ],
    );
  });

  test('BridgeBackend 评教 commit 投影成功失败未知未尝试四态且屏蔽原消息', () async {
    final client = _EvaluationBridgeClient(
      response: const BridgeEvaluationCoursesResponse(
        courses: <BridgeEvaluationCourse>[],
        progress: BridgeEvaluationProgress(
          totalCourses: 0,
          evaluatedCourses: 0,
          pendingCourses: 0,
        ),
      ),
      commitResult: const BridgeWriteCommitResult(
        operation: BridgeWriteOperation.evaluationSubmitCourses,
        success: false,
        message: 'raw-batch-message-must-not-pass',
        outcomeUnknown: true,
        resolvedRoute: BridgeConnectionMode.webVpn,
        evaluationResult: BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[
            BridgeEvaluationCourseResult(
              target: BridgeEvaluationSubmitTarget(
                rwid: 'task-success',
                wjid: 'form-success',
                kcdm: 'SUCCESS',
              ),
              courseName: '成功课程',
              outcome: BridgeEvaluationCourseOutcome.success,
              message: 'raw-success-message',
            ),
            BridgeEvaluationCourseResult(
              target: BridgeEvaluationSubmitTarget(
                rwid: 'task-failure',
                wjid: 'form-failure',
                kcdm: 'FAILURE',
              ),
              courseName: '失败课程',
              outcome: BridgeEvaluationCourseOutcome.failure,
              message: 'raw-failure-message',
            ),
            BridgeEvaluationCourseResult(
              target: BridgeEvaluationSubmitTarget(
                rwid: 'task-unknown',
                wjid: 'form-unknown',
                kcdm: 'UNKNOWN',
              ),
              courseName: '   ',
              outcome: BridgeEvaluationCourseOutcome.outcomeUnknown,
              message: 'raw-unknown-message',
            ),
            BridgeEvaluationCourseResult(
              target: BridgeEvaluationSubmitTarget(
                rwid: 'task-unattempted',
                wjid: 'form-unattempted',
                kcdm: 'UNATTEMPTED',
              ),
              courseName: '未尝试课程',
              outcome: BridgeEvaluationCourseOutcome.unattempted,
              message: 'raw-unattempted-message',
            ),
          ],
          success: false,
          outcomeUnknown: true,
        ),
      ),
    );

    final result = await BridgeBackend(client).commitWrite('intent-evaluation');
    final batch = result.evaluationResult!;

    expect(client.commitIntentIds, <String>['intent-evaluation']);
    expect(result.operation, WriteOperation.evaluationSubmitCourses);
    expect(result.success, isFalse);
    expect(result.outcomeUnknown, isTrue);
    expect(result.resolvedRoute, ConnectionMode.webvpn);
    expect(result.message, '教学评教提交结果无法确认，请刷新课程后核对');
    expect(
      batch.items.map((item) => item.outcome),
      EvaluationCourseOutcome.values,
    );
    expect(batch.items.map((item) => item.message), <String>[
      '评教提交成功',
      '评教提交失败',
      '评教提交结果无法确认',
      '未尝试提交',
    ]);
    expect(batch.items[2].courseName, '教学评教课程');
    expect(batch.success, isFalse);
    expect(batch.outcomeUnknown, isTrue);
    expect(
      <String>[
        result.message,
        ...batch.items.map((item) => item.message),
      ].join('|'),
      isNot(contains('raw-')),
    );
  });

  test('BridgeBackend 评教畸形 batch 一律闭合为 outcomeUnknown', () async {
    final malformedResults = <BridgeWriteCommitResult>[
      _evaluationCommitResult(batch: null),
      _evaluationCommitResult(
        batch: const BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[],
          success: false,
          outcomeUnknown: false,
        ),
      ),
      _evaluationCommitResult(
        batch: BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[
            _evaluationBridgeItem(
              rwid: '',
              suffix: 'empty',
              outcome: BridgeEvaluationCourseOutcome.failure,
            ),
          ],
          success: false,
          outcomeUnknown: false,
        ),
      ),
      _evaluationCommitResult(
        batch: BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[
            _evaluationBridgeItem(
              rwid: ' task-space',
              suffix: 'space',
              outcome: BridgeEvaluationCourseOutcome.failure,
            ),
          ],
          success: false,
          outcomeUnknown: false,
        ),
      ),
      _evaluationCommitResult(
        batch: BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[
            _evaluationBridgeItem(
              rwid: 'task-duplicate',
              suffix: 'duplicate',
              outcome: BridgeEvaluationCourseOutcome.failure,
            ),
            _evaluationBridgeItem(
              rwid: 'task-duplicate',
              suffix: 'duplicate',
              outcome: BridgeEvaluationCourseOutcome.failure,
            ),
          ],
          success: false,
          outcomeUnknown: false,
        ),
      ),
      _evaluationCommitResult(
        batch: BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[
            _evaluationBridgeItem(
              rwid: 'task-unattempted',
              suffix: 'unattempted',
              outcome: BridgeEvaluationCourseOutcome.unattempted,
            ),
          ],
          success: false,
          outcomeUnknown: false,
        ),
      ),
      _evaluationCommitResult(
        batch: BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[
            _evaluationBridgeItem(
              rwid: 'task-unknown',
              suffix: 'unknown',
              outcome: BridgeEvaluationCourseOutcome.outcomeUnknown,
            ),
            _evaluationBridgeItem(
              rwid: 'task-after-unknown',
              suffix: 'after-unknown',
              outcome: BridgeEvaluationCourseOutcome.success,
            ),
          ],
          success: false,
          outcomeUnknown: true,
        ),
      ),
      _evaluationCommitResult(
        batch: BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[
            _evaluationBridgeItem(
              rwid: 'task-failure-flags',
              suffix: 'failure-flags',
              outcome: BridgeEvaluationCourseOutcome.failure,
            ),
          ],
          success: true,
          outcomeUnknown: false,
        ),
        success: true,
      ),
      _evaluationCommitResult(
        batch: BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[
            _evaluationBridgeItem(
              rwid: 'task-unknown-flags',
              suffix: 'unknown-flags',
              outcome: BridgeEvaluationCourseOutcome.outcomeUnknown,
            ),
          ],
          success: false,
          outcomeUnknown: false,
        ),
      ),
      _evaluationCommitResult(
        batch: BridgeEvaluationBatchResult(
          items: <BridgeEvaluationCourseResult>[
            _evaluationBridgeItem(
              rwid: 'task-top-level',
              suffix: 'top-level',
              outcome: BridgeEvaluationCourseOutcome.success,
            ),
          ],
          success: true,
          outcomeUnknown: false,
        ),
        success: false,
      ),
    ];

    for (var index = 0; index < malformedResults.length; index += 1) {
      final backend = BridgeBackend(
        _EvaluationBridgeClient(
          response: const BridgeEvaluationCoursesResponse(
            courses: <BridgeEvaluationCourse>[],
            progress: BridgeEvaluationProgress(
              totalCourses: 0,
              evaluatedCourses: 0,
              pendingCourses: 0,
            ),
          ),
          commitResult: malformedResults[index],
        ),
      );
      await expectLater(
        backend.commitWrite('malformed-$index'),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.outcomeUnknown,
          ),
        ),
        reason: '畸形样例 $index 必须 fail-closed',
      );
    }
  });
}

class _EvaluationBridgeClient extends _CompatibleBridgeClient {
  _EvaluationBridgeClient({required this.response, this.commitResult});

  final BridgeEvaluationCoursesResponse response;
  final BridgeWriteCommitResult? commitResult;
  final List<BridgeConnectionMode> pinnedRoutes = <BridgeConnectionMode>[];
  final List<String> commitIntentIds = <String>[];
  int evaluationAllCalls = 0;
  int prepareCalls = 0;
  BridgeEvaluationSubmitCoursesRequest? prepareRequest;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #evaluationAll:
        evaluationAllCalls += 1;
        return Future<BridgeRoutedEvaluation>.value(
          BridgeRoutedEvaluation(data: response, route: _evaluationWebVpnRoute),
        );
      case #evaluationAllOnRoute:
        final route = invocation.namedArguments[#route] as BridgeConnectionMode;
        pinnedRoutes.add(route);
        return Future<BridgeCallerPinnedEvaluation>.value(
          BridgeCallerPinnedEvaluation(data: response, pinnedRoute: route),
        );
      case #prepareEvaluationSubmitCourses:
        prepareCalls += 1;
        prepareRequest =
            invocation.namedArguments[#request]
                as BridgeEvaluationSubmitCoursesRequest;
        return Future<BridgeWriteIntent>.value(
          _writeIntent(BridgeWriteOperation.evaluationSubmitCourses),
        );
      case #commitWrite:
        commitIntentIds.add(invocation.namedArguments[#intentId] as String);
        final result = commitResult;
        if (result == null) {
          throw StateError('测试未配置评教 commit 结果');
        }
        return Future<BridgeWriteCommitResult>.value(result);
      default:
        throw UnsupportedError(
          'unexpected bridge call: ${invocation.memberName}',
        );
    }
  }
}

const _evaluationWebVpnRoute = BridgeRouteDecision(
  policy: BridgeRoutePolicy.webVpn,
  resolvedRoute: BridgeConnectionMode.webVpn,
  network: BridgeNetworkState.offCampus,
  initialRoute: BridgeConnectionMode.webVpn,
  usedFallback: false,
);

BridgeWriteCommitResult _evaluationCommitResult({
  required BridgeEvaluationBatchResult? batch,
  bool success = false,
  bool outcomeUnknown = false,
}) => BridgeWriteCommitResult(
  operation: BridgeWriteOperation.evaluationSubmitCourses,
  success: success,
  message: '原始消息不得作为判定依据',
  outcomeUnknown: outcomeUnknown,
  resolvedRoute: BridgeConnectionMode.direct,
  evaluationResult: batch,
);

BridgeEvaluationCourseResult _evaluationBridgeItem({
  required String rwid,
  required String suffix,
  required BridgeEvaluationCourseOutcome outcome,
}) => BridgeEvaluationCourseResult(
  target: BridgeEvaluationSubmitTarget(
    rwid: rwid,
    wjid: 'form-$suffix',
    kcdm: 'COURSE-$suffix',
  ),
  courseName: '课程 $suffix',
  outcome: outcome,
  message: '原始消息 $suffix',
);
