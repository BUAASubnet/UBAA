part of '../widgets_test.dart';

void _registerBykcStateTests() {
  testWidgets('博雅选课只使用 typed action 且不依赖展示字段名称和值', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '展示字段已改名的课程',
                    fields: <FeatureField>[
                      FeatureField(label: '任意展示编号', value: '不是操作参数'),
                      FeatureField(label: '任意展示状态', value: '看起来不可选'),
                    ],
                    actions: <FeatureAction>[
                      BykcSelectAction(
                        courseId: 73,
                        eligibility: ActionEligibility.allowed,
                      ),
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
          onPrepareBykcWrite: (operation, courseId) async {
            prepareCalls++;
            expect(operation, WriteOperation.bykcSelectCourse);
            expect(courseId, 73);
            return WriteIntent(
              intentId: 'typed-select-73',
              operation: operation,
              targetSummary: '选择课程 73',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>[],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest',
            );
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

    final select = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '准备选课'),
    );
    expect(select.onPressed, isNotNull);
    await tester.tap(find.text('准备选课'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(find.text('选择课程 73'), findsOneWidget);
  });

  testWidgets('博雅选退课 action 缺失或资格非 allowed 时统一禁用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '缺失 action',
                    fields: <FeatureField>[
                      FeatureField(label: '课程 ID', value: '41'),
                      FeatureField(label: '状态', value: 'selected'),
                      FeatureField(label: '已选', value: '是'),
                    ],
                  ),
                  FeatureDetail(
                    title: '资格未知',
                    fields: <FeatureField>[
                      FeatureField(label: '课程 ID', value: '42'),
                      FeatureField(label: '状态', value: 'selected'),
                      FeatureField(label: '已选', value: '是'),
                    ],
                    actions: <FeatureAction>[
                      BykcSelectAction(
                        courseId: 42,
                        eligibility: ActionEligibility.unknown,
                      ),
                      BykcDeselectAction(
                        courseId: 42,
                        eligibility: ActionEligibility.unknown,
                      ),
                    ],
                  ),
                  FeatureDetail(
                    title: '明确拒绝',
                    fields: <FeatureField>[
                      FeatureField(label: '课程 ID', value: '43'),
                      FeatureField(label: '状态', value: '已选'),
                      FeatureField(label: '已选', value: '是'),
                    ],
                    actions: <FeatureAction>[
                      BykcSelectAction(
                        courseId: 43,
                        eligibility: ActionEligibility.denied,
                      ),
                      BykcDeselectAction(
                        courseId: 43,
                        eligibility: ActionEligibility.denied,
                      ),
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
          onPrepareBykcWrite: (_, __) async {
            prepareCalls++;
            throw StateError('不可选课程不应触发准备回调');
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

    final selects = tester.widgetList<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '准备选课'),
    );
    expect(selects, hasLength(3));
    expect(selects.every((button) => button.onPressed == null), isTrue);
    final deselects = tester.widgetList<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '准备退选'),
    );
    expect(deselects, hasLength(3));
    expect(deselects.every((button) => button.onPressed == null), isTrue);
    expect(prepareCalls, 0);
  });

  testWidgets('博雅签到状态明确不可用时禁用写入口并提示由 Core 判定', (tester) async {
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
                      FeatureField(label: '可签到', value: '否'),
                      FeatureField(label: '可签退', value: '否'),
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
          onPrepareBykcSignWrite: (_, __) async {
            prepareCalls++;
            throw StateError('should not be called');
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
    expect(find.text('当前不在可操作时间窗或状态不允许，具体条件由 Core 判定。'), findsOneWidget);
    await tester.tap(find.text('准备博雅签到'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 0);
    expect(find.text('确认博雅签到'), findsNothing);
  });

  testWidgets('博雅课程写入口只服从 typed 资格且退选目标不依赖展示字段', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '已选课程',
                    fields: <FeatureField>[
                      FeatureField(label: '展示记录', value: '9001'),
                      FeatureField(label: '已选', value: '否'),
                    ],
                    actions: <FeatureAction>[
                      BykcSelectAction(
                        courseId: 42,
                        eligibility: ActionEligibility.denied,
                      ),
                      BykcDeselectAction(
                        courseId: 9527,
                        eligibility: ActionEligibility.allowed,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var selectCalls = 0;
    var deselectCalls = 0;
    final deselectCourseIds = <int>[];
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
            if (operation == WriteOperation.bykcSelectCourse) {
              selectCalls++;
            } else if (operation == WriteOperation.bykcDeselectCourse) {
              deselectCalls++;
              deselectCourseIds.add(courseId);
            }
            return WriteIntent(
              intentId: 'status-${operation.name}',
              operation: operation,
              targetSummary: '课程 $courseId',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>[],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest',
            );
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

    final select = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '准备选课'),
    );
    final deselect = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '准备退选'),
    );
    expect(select.onPressed, isNull);
    expect(deselect.onPressed, isNotNull);
    expect(find.text('当前课程状态不支持该操作；最终资格和时间窗仍由 Core 校验。'), findsOneWidget);
    await tester.tap(find.text('准备退选'));
    await tester.pumpAndSettle();
    expect(deselectCalls, 1);
    expect(deselectCourseIds, <int>[9527]);
    expect(selectCalls, 0);
  });
}

void _registerCgyyStateTest() {
  testWidgets('场馆取消入口遵守冻结状态和四小时前截止时间', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.cgyy
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '已取消订单',
                    fields: <FeatureField>[
                      FeatureField(label: '订单编号', value: '18'),
                      FeatureField(label: '订单状态', value: '2'),
                      FeatureField(label: '审核状态', value: '1'),
                    ],
                  ),
                  FeatureDetail(
                    title: '审批驳回订单',
                    fields: <FeatureField>[
                      FeatureField(label: '订单编号', value: '19'),
                      FeatureField(label: '订单状态', value: '1'),
                      FeatureField(label: '审核状态', value: '-2'),
                    ],
                  ),
                  FeatureDetail(
                    title: '待审核订单',
                    fields: <FeatureField>[
                      FeatureField(label: '订单编号', value: '20'),
                      FeatureField(label: '订单状态', value: '1'),
                      FeatureField(label: '审核状态', value: '2'),
                    ],
                  ),
                  FeatureDetail(
                    title: '已过截止时间订单',
                    fields: <FeatureField>[
                      FeatureField(label: '订单编号', value: '21'),
                      FeatureField(label: '订单状态', value: '1'),
                      FeatureField(label: '审核状态', value: '1'),
                      FeatureField(label: '开始', value: '2020-01-01 10:00:00'),
                      FeatureField(label: '结束', value: '2020-01-01 11:00:00'),
                    ],
                  ),
                  FeatureDetail(
                    title: '未知状态订单',
                    fields: <FeatureField>[
                      FeatureField(label: '订单编号', value: '22'),
                      FeatureField(label: '订单状态', value: '9'),
                      FeatureField(label: '审核状态', value: '1'),
                    ],
                  ),
                  FeatureDetail(
                    title: '审核状态格式错误订单',
                    fields: <FeatureField>[
                      FeatureField(label: '订单编号', value: '23'),
                      FeatureField(label: '订单状态', value: '1'),
                      FeatureField(label: '审核状态', value: '待审核'),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
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
          onPrepareCancellationWrite: (_, __) async {
            fail('状态不可取消的订单不应触发准备回调');
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

    expect(find.text('准备取消订单'), findsOneWidget);
  });
}

void _registerLibbookStateTest() {
  testWidgets('图书馆预约取消入口遵守冻结状态码和状态名称', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.libbook
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '状态码已结束',
                    fields: <FeatureField>[
                      FeatureField(label: '预约 ID', value: 'booking-6'),
                      FeatureField(label: '状态码', value: '6'),
                      FeatureField(label: '状态', value: '有效'),
                    ],
                  ),
                  FeatureDetail(
                    title: '状态码已取消',
                    fields: <FeatureField>[
                      FeatureField(label: '预约 ID', value: 'booking-8'),
                      FeatureField(label: '状态码', value: '8'),
                      FeatureField(label: '状态', value: '有效'),
                    ],
                  ),
                  FeatureDetail(
                    title: '名称已取消',
                    fields: <FeatureField>[
                      FeatureField(label: '预约 ID', value: 'booking-name'),
                      FeatureField(label: '状态码', value: '1'),
                      FeatureField(label: '状态', value: '用户取消'),
                    ],
                  ),
                  FeatureDetail(
                    title: '有效预约',
                    fields: <FeatureField>[
                      FeatureField(label: '预约 ID', value: 'booking-ok'),
                      FeatureField(label: '状态码', value: '1'),
                      FeatureField(label: '状态', value: '有效'),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
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
          onPrepareCancellationWrite: (_, __) async {
            fail('已结束或已取消的预约不应触发准备回调');
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.apps_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('图书馆座位'));
    await tester.tap(find.text('图书馆座位'));
    await tester.pumpAndSettle();

    expect(find.text('准备取消预约'), findsOneWidget);
  });
}

void _registerSharedStateTests() {
  testWidgets('已有摘要但详情为空的 stale 状态保留摘要并提供重试', (tester) async {
    var retryCalls = 0;
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: feature == FeatureId.schedule
              ? FeatureLoadStatus.stale
              : FeatureLoadStatus.idle,
          summary: feature == FeatureId.schedule ? '旧摘要仍可查看' : null,
          error: feature == FeatureId.schedule
              ? const UiError(
                  code: UbaaErrorCode.networkError,
                  title: '网络暂时不可用',
                  message: '刷新失败，请重试。',
                  retryable: true,
                )
              : null,
          resolvedRoute: feature == FeatureId.schedule
              ? ConnectionMode.direct
              : null,
          details: const <FeatureDetail>[],
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {
            retryCalls++;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();

    expect(find.text('刷新失败，请重试。'), findsOneWidget);
    expect(find.text('旧摘要仍可查看'), findsOneWidget);
    expect(find.text('重试'), findsWidgets);
    await tester.tap(find.text('重试').last);
    await tester.pumpAndSettle();
    expect(retryCalls, 1);
  });

  testWidgets('十二项功能共享 loading、empty、failure、stale 状态矩阵', (tester) async {
    var retryCalls = 0;
    final statuses = <FeatureLoadStatus>[
      FeatureLoadStatus.loading,
      FeatureLoadStatus.empty,
      FeatureLoadStatus.failure,
      FeatureLoadStatus.stale,
    ];

    Future<void> openFeature(FeatureId feature) async {
      final ordinary = ordinaryFeatureIds.contains(feature);
      final selectedIcon = ordinary ? Icons.apps : Icons.auto_awesome;
      final unselectedIcon = ordinary
          ? Icons.apps_outlined
          : Icons.auto_awesome_outlined;
      final selectedFinder = find.byIcon(selectedIcon);
      final tabFinder = selectedFinder.evaluate().isNotEmpty
          ? selectedFinder
          : find.byIcon(unselectedIcon);
      await tester.tap(tabFinder.first);
      await tester.pump();
      final target = find.text(feature.title).first;
      await tester.scrollUntilVisible(
        target,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(target);
      await tester.pump();
      expect(find.text('返回功能列表'), findsOneWidget);
    }

    for (final status in statuses) {
      final snapshots = <FeatureId, FeatureSnapshot>{
        for (final feature in FeatureId.values)
          feature: FeatureSnapshot(
            feature: feature,
            status: status,
            summary: status == FeatureLoadStatus.stale ? '上次成功摘要' : null,
            details: status == FeatureLoadStatus.stale
                ? const <FeatureDetail>[FeatureDetail(title: '上次成功详情')]
                : const <FeatureDetail>[],
            error:
                status == FeatureLoadStatus.failure ||
                    status == FeatureLoadStatus.stale
                ? const UiError(
                    code: UbaaErrorCode.networkError,
                    title: '读取失败',
                    message: '测试读取失败',
                    retryable: true,
                  )
                : null,
          ),
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: UbaaTheme.light(),
          home: UbaaMainShell(
            user: const UserSummary(username: 'student'),
            snapshots: snapshots,
            routePolicy: RoutePolicy.auto,
            telemetryEnabled: false,
            onRefresh: () async {},
            onRetryFeature: (_) async => retryCalls++,
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      for (final feature in FeatureId.values) {
        await openFeature(feature);
        switch (status) {
          case FeatureLoadStatus.loading:
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
          case FeatureLoadStatus.empty:
            expect(find.text('暂无${feature.title}数据'), findsOneWidget);
          case FeatureLoadStatus.failure:
            expect(find.text('测试读取失败'), findsOneWidget);
            await tester.tap(find.text('重试').last);
            await tester.pump();
          case FeatureLoadStatus.stale:
            expect(find.text('测试读取失败'), findsOneWidget);
            expect(find.text('上次成功详情'), findsOneWidget);
            await tester.tap(find.text('重试').last);
            await tester.pump();
          case FeatureLoadStatus.idle || FeatureLoadStatus.success:
            fail('状态矩阵不应包含 ${status.name}');
        }
        await tester.tap(find.text('返回功能列表'));
        await tester.pump();
      }
    }
    expect(retryCalls, 24);
  });

  testWidgets('Core 返回未知结果时固定提示核对且不触发写后刷新', (tester) async {
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
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var refreshCalls = 0;
    final intent = WriteIntent(
      intentId: 'unknown-intent',
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
          onCommitWrite: (_) async => const WriteCommitResult(
            operation: WriteOperation.bykcSelectCourse,
            success: false,
            message: '上游响应超时',
            outcomeUnknown: true,
            resolvedRoute: ConnectionMode.direct,
          ),
          onWriteSuccess: (_) async => refreshCalls++,
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

    expect(find.text('提交结果不确定，请先刷新相关状态，不要重复提交。'), findsOneWidget);
    expect(find.text('上游响应超时'), findsNothing);
    expect(refreshCalls, 0);
  });

  testWidgets('提交异常时固定提示核对且不暴露具体业务状态', (tester) async {
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
          onCommitWrite: (_) async {
            throw Exception('fixture commit transport failure');
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
    await tester.tap(find.text('准备选课'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(find.text('提交结果不确定，请先刷新相关状态，不要重复提交。'), findsOneWidget);
    expect(find.text('相关课程状态'), findsNothing);
  });
}
