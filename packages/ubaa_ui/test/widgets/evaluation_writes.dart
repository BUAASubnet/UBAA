part of '../widgets_test.dart';

void _registerEvaluationWriteTests() {
  testWidgets('评教只消费 typed action 且展示字段改名不改变提交目标', (tester) async {
    const expectedTarget = EvaluationSubmitTarget(
      rwid: 'task-1',
      wjid: 'questionnaire-1',
      kcdm: 'K1',
      bpdm: 'teacher-1',
    );
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.evaluation
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课程 A',
                    subtitle: '教师 A',
                    fields: <FeatureField>[
                      FeatureField(label: '展示状态（已改名）', value: '已评'),
                      FeatureField(label: '展示任务（已改名）', value: 'wrong-task'),
                      FeatureField(label: '展示问卷（已改名）', value: 'wrong-form'),
                    ],
                    actions: <FeatureAction>[
                      EvaluationSubmitAction(
                        eligibility: ActionEligibility.allowed,
                        target: expectedTarget,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    var commitCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareEvaluationWrite: (targets) async {
            prepareCalls++;
            expect(targets, hasLength(1));
            expect(targets.single.rwid, 'task-1');
            expect(targets.single.wjid, 'questionnaire-1');
            expect(targets.single.kcdm, 'K1');
            expect(targets.single.bpdm, 'teacher-1');
            return WriteIntent(
              intentId: 'evaluation-1',
              operation: WriteOperation.evaluationSubmitCourses,
              targetSummary: '提交 1 门课程的教学评教',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>['提交后不可撤销'],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest',
            );
          },
          onCommitWrite: (intentId) async {
            commitCalls++;
            expect(intentId, 'evaluation-1');
            return const WriteCommitResult(
              operation: WriteOperation.evaluationSubmitCourses,
              success: true,
              message: '评教结果已提交，请刷新确认',
              outcomeUnknown: false,
            );
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教学评教'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备提交评教'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认教学评教'), findsNWidgets(2));
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(find.text('评教结果已提交，请刷新确认'), findsOneWidget);
  });

  testWidgets('评教可显式勾选多门待评课程后批量进入确认页', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    const firstTarget = EvaluationSubmitTarget(
      rwid: 'task-a',
      wjid: 'questionnaire-a',
      kcdm: 'KA',
      bpdm: 'teacher-a',
    );
    const secondTarget = EvaluationSubmitTarget(
      rwid: 'task-b',
      wjid: 'questionnaire-b',
      kcdm: 'KB',
      bpdm: 'teacher-b',
    );
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.evaluation
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课程 A',
                    subtitle: '教师 A',
                    fields: <FeatureField>[
                      FeatureField(label: '状态', value: '待评'),
                      FeatureField(label: '课程 ID', value: 'course-shared'),
                      FeatureField(label: '任务 ID', value: 'task-a'),
                      FeatureField(label: '问卷 ID', value: 'questionnaire-a'),
                      FeatureField(label: '课程代码', value: 'KA'),
                      FeatureField(label: '模型 ID', value: 'MA'),
                    ],
                    actions: <FeatureAction>[
                      EvaluationSubmitAction(
                        eligibility: ActionEligibility.allowed,
                        target: firstTarget,
                      ),
                    ],
                  ),
                  FeatureDetail(
                    title: '课程 B',
                    subtitle: '教师 B',
                    fields: <FeatureField>[
                      FeatureField(label: '状态', value: '待评'),
                      FeatureField(label: '课程 ID', value: 'course-shared'),
                      FeatureField(label: '任务 ID', value: 'task-b'),
                      FeatureField(label: '问卷 ID', value: 'questionnaire-b'),
                      FeatureField(label: '课程代码', value: 'KB'),
                      FeatureField(label: '模型 ID', value: 'MB'),
                    ],
                    actions: <FeatureAction>[
                      EvaluationSubmitAction(
                        eligibility: ActionEligibility.allowed,
                        target: secondTarget,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    var commitCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareEvaluationWrite: (targets) async {
            prepareCalls++;
            expect(targets.map((target) => target.selectionKey), <String>[
              firstTarget.selectionKey,
              secondTarget.selectionKey,
            ]);
            return WriteIntent(
              intentId: 'evaluation-batch',
              operation: WriteOperation.evaluationSubmitCourses,
              targetSummary: '提交 2 门课程的教学评教',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>['提交后不可撤销'],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest-batch',
            );
          },
          onCommitWrite: (intentId) async {
            commitCalls++;
            expect(intentId, 'evaluation-batch');
            return const WriteCommitResult(
              operation: WriteOperation.evaluationSubmitCourses,
              success: true,
              message: '评教结果已提交，请刷新确认',
              outcomeUnknown: false,
            );
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教学评教'));
    await tester.pumpAndSettle();

    expect(find.text('准备批量评教'), findsOneWidget);
    expect(find.text('已选择 0 门待评课程'), findsOneWidget);
    final first = find.byKey(
      ValueKey<String>('evaluation-${firstTarget.selectionKey}'),
    );
    final second = find.byKey(
      ValueKey<String>('evaluation-${secondTarget.selectionKey}'),
    );
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.ensureVisible(second);
    await tester.tap(second);
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 门待评课程'), findsOneWidget);
    await tester.tap(find.text('准备批量评教'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认教学评教'), findsNWidgets(2));
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(find.text('评教结果已提交，请刷新确认'), findsOneWidget);
  });

  testWidgets('评教 denied unknown 或缺少 action 时均不可提交', (tester) async {
    const target = EvaluationSubmitTarget(
      rwid: 'task-safe',
      wjid: 'questionnaire-safe',
      kcdm: 'course-safe',
    );
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.evaluation
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '明确拒绝',
                    fields: <FeatureField>[
                      FeatureField(label: '状态', value: '待评'),
                      FeatureField(label: '课程 ID', value: 'denied'),
                      FeatureField(label: '任务 ID', value: 'task-safe'),
                      FeatureField(label: '问卷 ID', value: 'questionnaire-safe'),
                      FeatureField(label: '课程代码', value: 'course-safe'),
                      FeatureField(label: '模型 ID', value: 'model-safe'),
                    ],
                    actions: <FeatureAction>[
                      EvaluationSubmitAction(
                        eligibility: ActionEligibility.denied,
                        target: target,
                      ),
                    ],
                  ),
                  FeatureDetail(
                    title: '状态未知',
                    fields: <FeatureField>[
                      FeatureField(label: '状态', value: '待评'),
                      FeatureField(label: '课程 ID', value: 'unknown'),
                      FeatureField(label: '任务 ID', value: 'task-safe'),
                      FeatureField(label: '问卷 ID', value: 'questionnaire-safe'),
                      FeatureField(label: '课程代码', value: 'course-safe'),
                      FeatureField(label: '模型 ID', value: 'model-safe'),
                    ],
                    actions: <FeatureAction>[
                      EvaluationSubmitAction(
                        eligibility: ActionEligibility.unknown,
                        target: target,
                      ),
                    ],
                  ),
                  FeatureDetail(
                    title: '没有 typed action',
                    fields: <FeatureField>[
                      FeatureField(label: '状态', value: '待评'),
                      FeatureField(label: '课程 ID', value: 'missing-action'),
                      FeatureField(label: '任务 ID', value: 'task-safe'),
                      FeatureField(label: '问卷 ID', value: 'questionnaire-safe'),
                      FeatureField(label: '课程代码', value: 'course-safe'),
                      FeatureField(label: '模型 ID', value: 'model-safe'),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareEvaluationWrite: (_) async {
            prepareCalls++;
            throw StateError('不可到达');
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教学评教'));
    await tester.pumpAndSettle();

    expect(find.text('准备提交评教'), findsNothing);
    expect(prepareCalls, 0);
  });

  testWidgets('评教 prepare 返回错误 operation 时丢弃 intent 且不进入确认页', (tester) async {
    const target = EvaluationSubmitTarget(
      rwid: 'task-safe',
      wjid: 'questionnaire-safe',
      kcdm: 'course-safe',
    );
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.evaluation
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课程',
                    fields: <FeatureField>[
                      FeatureField(label: '状态', value: '待评'),
                      FeatureField(label: '课程 ID', value: 'course-safe'),
                      FeatureField(label: '任务 ID', value: 'task-safe'),
                      FeatureField(label: '问卷 ID', value: 'questionnaire-safe'),
                      FeatureField(label: '课程代码', value: 'course-safe'),
                      FeatureField(label: '模型 ID', value: 'model-safe'),
                    ],
                    actions: <FeatureAction>[
                      EvaluationSubmitAction(
                        eligibility: ActionEligibility.allowed,
                        target: target,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    String? discardedIntent;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareEvaluationWrite: (_) async => WriteIntent(
            intentId: 'wrong-operation',
            operation: WriteOperation.ygdkSubmit,
            targetSummary: '错误操作',
            resolvedRoute: ConnectionMode.direct,
            warnings: const <String>[],
            expiresAt: DateTime.now().add(const Duration(minutes: 2)),
            requestDigest: 'digest',
          ),
          onDiscardWriteIntent: (intentId) async {
            discardedIntent = intentId;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教学评教'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备提交评教'));
    await tester.pumpAndSettle();

    expect(discardedIntent, 'wrong-operation');
    expect(find.text('确认阳光打卡'), findsNothing);
  });

  void registerReadbackCase({
    required String name,
    WriteCommitResult? result,
    UiError? error,
    required bool expectsReadback,
    bool readbackThrows = false,
    String? expectedMessage,
  }) {
    testWidgets(name, (tester) async {
      const target = EvaluationSubmitTarget(
        rwid: 'task-readback',
        wjid: 'questionnaire-readback',
        kcdm: 'course-readback',
      );
      final snapshots = <FeatureId, FeatureSnapshot>{
        for (final feature in FeatureId.values)
          feature: FeatureSnapshot(
            feature: feature,
            status: FeatureLoadStatus.success,
            summary: '已加载',
            details: feature == FeatureId.evaluation
                ? const <FeatureDetail>[
                    FeatureDetail(
                      title: '回读课程',
                      actions: <FeatureAction>[
                        EvaluationSubmitAction(
                          eligibility: ActionEligibility.allowed,
                          target: target,
                        ),
                      ],
                    ),
                  ]
                : const <FeatureDetail>[],
          ),
      };
      var commitCalls = 0;
      final readbackRoutes = <ConnectionMode>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: UbaaTheme.light(),
          home: UbaaMainShell(
            user: const UserSummary(username: 'student'),
            snapshots: snapshots,
            routePolicy: RoutePolicy.auto,
            telemetryEnabled: false,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onPrepareEvaluationWrite: (_) async => WriteIntent(
              intentId: 'evaluation-readback',
              operation: WriteOperation.evaluationSubmitCourses,
              targetSummary: '提交回读课程的教学评教',
              resolvedRoute: ConnectionMode.webvpn,
              warnings: const <String>['提交后不可撤销'],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest-readback',
            ),
            onCommitWrite: (_) async {
              commitCalls++;
              if (error case final value?) throw value;
              return result!;
            },
            onRefreshEvaluationAfterWrite: ({required expectedRoute}) async {
              readbackRoutes.add(expectedRoute);
              if (readbackThrows) throw StateError('脱敏回读失败');
            },
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('教学评教'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('准备提交评教'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认提交'));
      await tester.pumpAndSettle();

      expect(commitCalls, 1);
      expect(
        readbackRoutes,
        expectsReadback
            ? const <ConnectionMode>[ConnectionMode.webvpn]
            : isEmpty,
      );
      if (expectedMessage case final message?) {
        expect(find.text(message), findsOneWidget);
      }
    });
  }

  registerReadbackCase(
    name: '评教确定成功恰好一次按 intent 路线回读',
    result: const WriteCommitResult(
      operation: WriteOperation.evaluationSubmitCourses,
      success: true,
      message: '评教已提交',
      outcomeUnknown: false,
      evaluationResult: EvaluationBatchResult(
        items: <EvaluationCourseResult>[],
        success: true,
        outcomeUnknown: false,
      ),
    ),
    expectsReadback: true,
  );
  registerReadbackCase(
    name: '评教确定部分失败仍恰好一次按 intent 路线回读',
    result: const WriteCommitResult(
      operation: WriteOperation.evaluationSubmitCourses,
      success: false,
      message: '部分课程未提交',
      outcomeUnknown: false,
      evaluationResult: EvaluationBatchResult(
        items: <EvaluationCourseResult>[
          EvaluationCourseResult(
            target: EvaluationSubmitTarget(
              rwid: 'task-success',
              wjid: 'questionnaire-success',
              kcdm: 'course-success',
            ),
            courseName: '成功课程',
            outcome: EvaluationCourseOutcome.success,
            message: '已提交',
          ),
          EvaluationCourseResult(
            target: EvaluationSubmitTarget(
              rwid: 'task-failure',
              wjid: 'questionnaire-failure',
              kcdm: 'course-failure',
            ),
            courseName: '失败课程',
            outcome: EvaluationCourseOutcome.failure,
            message: '未提交',
          ),
        ],
        success: false,
        outcomeUnknown: false,
      ),
    ),
    expectsReadback: true,
  );
  registerReadbackCase(
    name: '评教返回 outcomeUnknown 恰好一次按 intent 路线回读',
    result: const WriteCommitResult(
      operation: WriteOperation.evaluationSubmitCourses,
      success: false,
      message: '结果待核对',
      outcomeUnknown: true,
      evaluationResult: EvaluationBatchResult(
        items: <EvaluationCourseResult>[],
        success: false,
        outcomeUnknown: true,
      ),
    ),
    expectsReadback: true,
    expectedMessage: '提交结果不确定，请先刷新相关状态，不要重复提交。',
  );
  registerReadbackCase(
    name: '评教抛出 outcomeUnknown 恰好一次按 intent 路线回读',
    error: const UiError(
      code: UbaaErrorCode.outcomeUnknown,
      title: '结果待核对',
      message: '结果暂时无法确认',
    ),
    expectsReadback: true,
    expectedMessage: '提交结果不确定，请先刷新相关状态，不要重复提交。',
  );
  registerReadbackCase(
    name: '评教未知结果的回读失败不升级结论也不重发',
    result: const WriteCommitResult(
      operation: WriteOperation.evaluationSubmitCourses,
      success: false,
      message: '结果待核对',
      outcomeUnknown: true,
      evaluationResult: EvaluationBatchResult(
        items: <EvaluationCourseResult>[],
        success: false,
        outcomeUnknown: true,
      ),
    ),
    expectsReadback: true,
    readbackThrows: true,
    expectedMessage: '提交结果不确定，请先刷新相关状态，不要重复提交。',
  );
  registerReadbackCase(
    name: '评教任意 commit 错误仍回读原路线且不重发',
    error: const UiError(
      code: UbaaErrorCode.upstreamChanged,
      title: '提交失败',
      message: '上游状态已变化',
    ),
    expectsReadback: true,
  );
}
