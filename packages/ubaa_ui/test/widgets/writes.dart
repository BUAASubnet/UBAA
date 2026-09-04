part of '../widgets_test.dart';

void _registerInitialWriteTests() {
  testWidgets('博雅课程写操作先展示一次性确认且仅在确认后提交', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课程',
                    fields: <FeatureField>[
                      FeatureField(label: '课程 ID', value: '42'),
                    ],
                    actions: <FeatureAction>[
                      BykcSelectAction(
                        courseId: 42,
                        eligibility: ActionEligibility.allowed,
                      ),
                      BykcDeselectAction(
                        courseId: 42,
                        eligibility: ActionEligibility.allowed,
                      ),
                      BykcSignAction(
                        courseId: 42,
                        kind: BykcSignKind.signIn,
                        eligibility: ActionEligibility.allowed,
                        requiresCoordinates: false,
                      ),
                      BykcSignAction(
                        courseId: 42,
                        kind: BykcSignKind.signOut,
                        eligibility: ActionEligibility.allowed,
                        requiresCoordinates: true,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    var deselectCalls = 0;
    var signCalls = 0;
    final signTypes = <int>[];
    var commitCalls = 0;
    var refreshCalls = 0;
    final discardedIntentIds = <String>[];
    String? committedIntent;
    final intent = WriteIntent(
      intentId: 'intent-42',
      operation: WriteOperation.bykcSelectCourse,
      targetSummary: '选择课程 42',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>['提交后请刷新已选课程确认结果'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
    );
    final signIntent = WriteIntent(
      intentId: 'sign-intent-42',
      operation: WriteOperation.bykcSignCourse,
      targetSummary: '博雅课程 42 签到',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>['位置或时间窗要求由 Core 校验'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'sign-digest',
    );
    final deselectIntent = WriteIntent(
      intentId: 'deselect-intent-42',
      operation: WriteOperation.bykcDeselectCourse,
      targetSummary: '退选课程 42',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>['请确认退选课程和截止时间'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'deselect-digest',
    );
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
          onPrepareBykcWrite: (operation, courseId) async {
            expect(courseId, 42);
            if (operation == WriteOperation.bykcSelectCourse) {
              prepareCalls++;
              return intent;
            }
            expect(operation, WriteOperation.bykcDeselectCourse);
            deselectCalls++;
            return deselectIntent;
          },
          onPrepareBykcSignWrite: (action) async {
            signCalls++;
            expect(action.courseId, 42);
            signTypes.add(action.signType);
            expect(action.signType, anyOf(1, 2));
            return signIntent;
          },
          onDiscardWriteIntent: (intentId) async {
            discardedIntentIds.add(intentId);
          },
          onCommitWrite: (intentId) async {
            commitCalls++;
            committedIntent = intentId;
            final operation = intentId == 'deselect-intent-42'
                ? WriteOperation.bykcDeselectCourse
                : WriteOperation.bykcSelectCourse;
            return WriteCommitResult(
              operation: operation,
              success: true,
              message: operation == WriteOperation.bykcDeselectCourse
                  ? '退选结果已提交，请刷新已选课程确认'
                  : '已提交，请刷新已选课程确认',
              outcomeUnknown: false,
              resolvedRoute: ConnectionMode.direct,
            );
          },
          onWriteSuccess: (operation, _) async {
            expect(
              operation,
              anyOf(
                WriteOperation.bykcSelectCourse,
                WriteOperation.bykcDeselectCourse,
              ),
            );
            refreshCalls++;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('博雅课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备博雅签到'));
    await tester.pumpAndSettle();
    expect(signCalls, 1);
    expect(signTypes, <int>[1]);
    expect(commitCalls, 0);
    expect(find.text('确认博雅签到'), findsNWidgets(2));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(discardedIntentIds, <String>['sign-intent-42']);
    await tester.tap(find.text('准备博雅签到'));
    await tester.pumpAndSettle();
    expect(signCalls, 2);
    expect(signTypes, <int>[1, 1]);
    expect(find.text('确认博雅签到'), findsNWidgets(2));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(discardedIntentIds, <String>['sign-intent-42', 'sign-intent-42']);
    await tester.tap(find.text('准备博雅签退'));
    await tester.pumpAndSettle();
    expect(signCalls, 3);
    expect(signTypes, <int>[1, 1, 2]);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备选课'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认博雅选课'), findsNWidgets(2));
    expect(find.text('选择课程 42'), findsOneWidget);
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(refreshCalls, 1);
    expect(committedIntent, 'intent-42');
    expect(find.text('已提交，请刷新已选课程确认'), findsOneWidget);

    await tester.tap(find.text('准备退选'));
    await tester.pumpAndSettle();
    expect(deselectCalls, 1);
    expect(commitCalls, 1);
    expect(find.text('确认博雅退选'), findsNWidgets(2));
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 2);
    expect(committedIntent, 'deselect-intent-42');
  });

  testWidgets('丢弃待确认意图首次失败保留，第二次成功清理', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课程',
                    actions: <FeatureAction>[
                      BykcSignAction(
                        courseId: 42,
                        kind: BykcSignKind.signIn,
                        eligibility: ActionEligibility.allowed,
                        requiresCoordinates: false,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    var discardCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareBykcSignWrite: (_) async {
            prepareCalls++;
            return WriteIntent(
              intentId: 'intent-retained',
              operation: WriteOperation.bykcSignCourse,
              targetSummary: '课程签到',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>[],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest',
            );
          },
          onDiscardWriteIntent: (_) async {
            discardCalls++;
            if (discardCalls == 1) throw StateError('脱敏丢弃失败');
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('博雅课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备博雅签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(prepareCalls, 1);
    expect(discardCalls, 1);
    expect(find.text('确认博雅签到'), findsNWidgets(2));
    expect(find.text('暂时无法取消待确认操作，请重试。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(discardCalls, 2);
    expect(find.text('确认博雅签到'), findsNothing);
  });

  testWidgets('prepare 在主界面卸载后返回时 best-effort 释放晚到的 intent', (tester) async {
    final prepared = Completer<WriteIntent>();
    final discardedIntentIds = <String>[];
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课程',
                    actions: <FeatureAction>[
                      BykcSignAction(
                        courseId: 42,
                        kind: BykcSignKind.signIn,
                        eligibility: ActionEligibility.allowed,
                        requiresCoordinates: false,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareBykcSignWrite: (_) => prepared.future,
          onDiscardWriteIntent: (intentId) async {
            discardedIntentIds.add(intentId);
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('博雅课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备博雅签到'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    prepared.complete(
      WriteIntent(
        intentId: 'intent-after-unmount',
        operation: WriteOperation.bykcSignCourse,
        targetSummary: '课程签到',
        resolvedRoute: ConnectionMode.direct,
        warnings: const <String>[],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'digest',
      ),
    );
    await tester.pumpAndSettle();

    expect(discardedIntentIds, <String>['intent-after-unmount']);
  });

  testWidgets('丢弃尚未完成时保留确认页并禁用取消与提交', (tester) async {
    final discardFinished = Completer<void>();
    var discardCalls = 0;
    var commitCalls = 0;
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课程',
                    actions: <FeatureAction>[
                      BykcSignAction(
                        courseId: 42,
                        kind: BykcSignKind.signIn,
                        eligibility: ActionEligibility.allowed,
                        requiresCoordinates: false,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareBykcSignWrite: (_) async => WriteIntent(
            intentId: 'intent-pending-discard',
            operation: WriteOperation.bykcSignCourse,
            targetSummary: '课程签到',
            resolvedRoute: ConnectionMode.direct,
            warnings: const <String>[],
            expiresAt: DateTime.now().add(const Duration(minutes: 2)),
            requestDigest: 'digest',
          ),
          onDiscardWriteIntent: (intentId) async {
            discardCalls++;
            expect(intentId, 'intent-pending-discard');
            await discardFinished.future;
          },
          onCommitWrite: (_) async {
            commitCalls++;
            throw StateError('丢弃期间不应提交');
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('博雅课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备博雅签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pump();

    expect(discardCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认博雅签到'), findsNWidgets(2));
    expect(find.text('正在取消'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '正在取消'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认提交'))
          .onPressed,
      isNull,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(FilledButton, '确认提交'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('正在取消'), warnIfMissed: false);
    await tester.pump();
    expect(discardCalls, 1);
    expect(commitCalls, 0);

    discardFinished.complete();
    await tester.pumpAndSettle();
    expect(find.text('确认博雅签到'), findsNothing);
    expect(discardCalls, 1);
  });

  testWidgets('课堂签到从公开课程编号准备并在确认后提交', (tester) async {
    const expectedAction = SigninPerformAction(
      scheduleId: 'schedule-7',
      eligibility: ActionEligibility.allowed,
    );
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.signin
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '课堂签到课程',
                    fields: <FeatureField>[
                      FeatureField(label: '课程 ID', value: '误导目标'),
                      FeatureField(label: '签到状态', value: '已签到'),
                    ],
                    actions: <FeatureAction>[expectedAction],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    var commitCalls = 0;
    var refreshCalls = 0;
    final intent = WriteIntent(
      intentId: 'signin-intent',
      operation: WriteOperation.signinPerform,
      targetSummary: '课堂签到课程',
      resolvedRoute: ConnectionMode.webvpn,
      warnings: const <String>['提交后请刷新今日签到状态确认结果'],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
    );
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
          onPrepareSigninWrite: (action) async {
            prepareCalls++;
            expect(identical(action, expectedAction), isTrue);
            expect(action.scheduleId, 'schedule-7');
            expect(action.eligibility, ActionEligibility.allowed);
            return intent;
          },
          onCommitWrite: (intentId) async {
            commitCalls++;
            expect(intentId, 'signin-intent');
            return const WriteCommitResult(
              operation: WriteOperation.signinPerform,
              success: true,
              message: '签到结果已提交，请刷新确认',
              outcomeUnknown: false,
            );
          },
          onWriteSuccess: (operation, _) async {
            expect(operation, WriteOperation.signinPerform);
            refreshCalls++;
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
    await tester.tap(find.text('课堂签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备签到'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认课堂签到'), findsNWidgets(2));
    expect(find.text('WebVPN'), findsOneWidget);
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(refreshCalls, 1);
    expect(find.text('签到结果已提交，请刷新确认'), findsOneWidget);
  });
}

Future<int> _pumpBykcCommitError(WidgetTester tester, Object error) async {
  var refreshCalls = 0;
  final snapshots = <FeatureId, FeatureSnapshot>{
    for (final feature in FeatureId.values)
      feature: FeatureSnapshot(
        feature: feature,
        status: FeatureLoadStatus.success,
        summary: '已加载',
        details: feature == FeatureId.bykc
            ? const <FeatureDetail>[
                FeatureDetail(
                  title: '课程',
                  actions: <FeatureAction>[
                    BykcSelectAction(
                      courseId: 42,
                      eligibility: ActionEligibility.allowed,
                    ),
                  ],
                ),
              ]
            : const <FeatureDetail>[],
      ),
  };
  final intent = WriteIntent(
    intentId: 'throwing-intent',
    operation: WriteOperation.bykcSelectCourse,
    targetSummary: '选择课程 42',
    resolvedRoute: ConnectionMode.direct,
    warnings: const <String>[],
    expiresAt: DateTime.now().add(const Duration(minutes: 2)),
    requestDigest: 'digest',
  );
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
        onPrepareBykcWrite: (_, __) async => intent,
        onCommitWrite: (_) async => throw error,
        onWriteSuccess: (_, __) async => refreshCalls++,
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
        onTelemetryChanged: (_) {},
      ),
    ),
  );
  await tester.tap(find.text('博雅课程'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('准备选课'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认提交'));
  await tester.pumpAndSettle();
  return refreshCalls;
}

void _registerCgyyCancellationWriteTest() {
  testWidgets('场馆订单取消只从公开订单编号进入确认页', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.cgyy
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '羽毛球馆订单',
                    fields: <FeatureField>[
                      FeatureField(label: '订单编号', value: '17'),
                      FeatureField(label: '订单状态', value: '1'),
                      FeatureField(label: '审核状态', value: '2'),
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
          onPrepareCancellationWrite: (operation, targetId) async {
            prepareCalls++;
            expect(operation, WriteOperation.cgyyCancelOrder);
            expect(targetId, '17');
            return WriteIntent(
              intentId: 'cancel-17',
              operation: operation,
              targetSummary: '取消订单 17',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>['取消后请刷新订单列表确认状态'],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest',
            );
          },
          onCommitWrite: (intentId) async {
            commitCalls++;
            expect(intentId, 'cancel-17');
            return const WriteCommitResult(
              operation: WriteOperation.cgyyCancelOrder,
              success: true,
              message: '订单取消结果已提交，请刷新确认',
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
    await tester.tap(find.text('场馆预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备取消订单'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认取消场馆订单'), findsNWidgets(2));
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(find.text('订单取消结果已提交，请刷新确认'), findsOneWidget);
  });
}

void _registerRemainingWriteTests() {
  testWidgets('待评课程从公开字段准备评教且确认后才提交', (tester) async {
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
                      FeatureField(label: '课程 ID', value: 'course-1'),
                      FeatureField(label: '任务 ID', value: 'task-1'),
                      FeatureField(label: '问卷 ID', value: 'questionnaire-1'),
                      FeatureField(label: '课程代码', value: 'K1'),
                      FeatureField(label: '模型 ID', value: 'M1'),
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
          onPrepareEvaluationWrite: (courses) async {
            prepareCalls++;
            expect(courses.single.id, 'course-1');
            expect(courses.single.rwid, 'task-1');
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
                      FeatureField(label: '课程 ID', value: 'course-a'),
                      FeatureField(label: '任务 ID', value: 'task-a'),
                      FeatureField(label: '问卷 ID', value: 'questionnaire-a'),
                      FeatureField(label: '课程代码', value: 'KA'),
                      FeatureField(label: '模型 ID', value: 'MA'),
                    ],
                  ),
                  FeatureDetail(
                    title: '课程 B',
                    subtitle: '教师 B',
                    fields: <FeatureField>[
                      FeatureField(label: '状态', value: '待评'),
                      FeatureField(label: '课程 ID', value: 'course-b'),
                      FeatureField(label: '任务 ID', value: 'task-b'),
                      FeatureField(label: '问卷 ID', value: 'questionnaire-b'),
                      FeatureField(label: '课程代码', value: 'KB'),
                      FeatureField(label: '模型 ID', value: 'MB'),
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
          onPrepareEvaluationWrite: (courses) async {
            prepareCalls++;
            expect(courses.map((course) => course.id), <String>[
              'course-a',
              'course-b',
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
    final first = find.byKey(const ValueKey<String>('evaluation-course-a'));
    final second = find.byKey(const ValueKey<String>('evaluation-course-b'));
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

  testWidgets('写入确认显示实际路线并防止过期提交', (tester) async {
    final intent = WriteIntent(
      intentId: 'intent',
      operation: WriteOperation.libbookCancelBooking,
      targetSummary: '取消一条图书馆预约',
      resolvedRoute: ConnectionMode.webvpn,
      warnings: const <String>['取消操作可能不可恢复'],
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      requestDigest: 'digest',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: WriteConfirmationView(
          intent: intent,
          onCancel: () {},
          onConfirm: () async {},
        ),
      ),
    );
    expect(find.text('WebVPN'), findsOneWidget);
    expect(find.text('意图已过期'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '意图已过期'),
    );
    expect(submit.onPressed, isNull);
  });
}
