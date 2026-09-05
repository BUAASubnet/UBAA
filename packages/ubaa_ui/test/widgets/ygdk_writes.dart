part of '../widgets_test.dart';

void _registerYgdkWriteResultTests() {
  testWidgets(
    '''阳光打卡缺少 prepare picker readback commit 或 discard
任一能力时隐藏入口''',
    (tester) async {
      final prepare = (YgdkSubmitInput _) async => _validYgdkIntent();
      final commit = (String _) async => const WriteCommitResult(
        operation: WriteOperation.ygdkSubmit,
        success: true,
        message: '阳光打卡已提交',
        outcomeUnknown: false,
      );
      final discard = (String _) async {};
      final refresh = ({required ConnectionMode expectedRoute}) async {};
      final cases =
          <
            ({
              String missing,
              YgdkSubmitPreparer? prepare,
              YgdkPhotoPicker? picker,
              Future<WriteCommitResult> Function(String intentId)? commit,
              WriteIntentDiscarder? discard,
              YgdkSubmissionRefresher? refresh,
            })
          >[
            (
              missing: 'prepare',
              prepare: null,
              picker: _validYgdkPhoto,
              commit: commit,
              discard: discard,
              refresh: refresh,
            ),
            (
              missing: 'picker',
              prepare: prepare,
              picker: null,
              commit: commit,
              discard: discard,
              refresh: refresh,
            ),
            (
              missing: 'readback',
              prepare: prepare,
              picker: _validYgdkPhoto,
              commit: commit,
              discard: discard,
              refresh: null,
            ),
            (
              missing: 'commit',
              prepare: prepare,
              picker: _validYgdkPhoto,
              commit: null,
              discard: discard,
              refresh: refresh,
            ),
            (
              missing: 'discard',
              prepare: prepare,
              picker: _validYgdkPhoto,
              commit: commit,
              discard: null,
              refresh: refresh,
            ),
          ];

      for (final item in cases) {
        await _pumpYgdkShell(
          tester,
          key: ValueKey<String>('missing-${item.missing}'),
          prepare: item.prepare,
          picker: item.picker,
          commit: item.commit,
          discard: item.discard,
          refresh: item.refresh,
        );
        await _openYgdkDetails(tester);
        expect(
          find.text('准备阳光打卡'),
          findsNothing,
          reason: '缺少 ${item.missing} 时必须 fail-closed',
        );
      }
    },
  );

  testWidgets(
    '''阳光打卡确认前 prepare picker readback commit 或 discard
任一能力丢失都失败关闭''',
    (tester) async {
      for (final missing in <String>[
        'prepare',
        'picker',
        'readback',
        'commit',
        'discard',
      ]) {
        final missingCapability = ValueNotifier<String?>(null);
        var commitCalls = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: UbaaTheme.light(),
            home: ValueListenableBuilder<String?>(
              valueListenable: missingCapability,
              builder: (context, unavailable, _) => coordinatedShell(
                key: ValueKey<String>('confirm-missing-$missing'),
                user: const UserSummary(username: 'student'),
                snapshots: _ygdkSnapshots(),
                routePolicy: RoutePolicy.auto,
                telemetryEnabled: false,
                onRefresh: () async {},
                onRetryFeature: (_) async {},
                onPrepareYgdkSubmitWrite: unavailable == 'prepare'
                    ? null
                    : (_) async => _validYgdkIntent(),
                onPickYgdkPhoto: unavailable == 'picker'
                    ? null
                    : _validYgdkPhoto,
                onCommitWrite: unavailable == 'commit'
                    ? null
                    : (_) async {
                        commitCalls++;
                        return const WriteCommitResult(
                          operation: WriteOperation.ygdkSubmit,
                          success: true,
                          message: '不应提交',
                          outcomeUnknown: false,
                        );
                      },
                onRefreshYgdkAfterWrite: unavailable == 'readback'
                    ? null
                    : ({required expectedRoute}) async {},
                onDiscardWriteIntent: unavailable == 'discard'
                    ? null
                    : (_) async {},
                onLogout: () async {},
                onLogoutAndClearAccount: () async {},
                onRoutePolicyChanged: (_) {},
                onTelemetryChanged: (_) {},
              ),
            ),
          ),
        );

        await _openAndFillYgdkForm(tester);
        await tester.tap(find.text('继续确认'));
        await tester.pumpAndSettle();
        missingCapability.value = missing;
        await tester.pump();
        await tester.tap(find.text('确认提交'));
        await tester.pumpAndSettle();

        expect(commitCalls, 0, reason: '缺少 $missing 时不得调用 commit');
        expect(
          find.text('阳光打卡能力不完整；尚未提交任何写请求。'),
          findsOneWidget,
          reason: '缺少 $missing 时必须明确失败关闭',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        missingCapability.dispose();
      }
    },
  );

  testWidgets('阳光打卡 prepare 返回异领域意图时丢弃并失败关闭', (tester) async {
    final discardedIntentIds = <String>[];
    var commitCalls = 0;
    await _pumpYgdkShell(
      tester,
      key: const ValueKey<String>('mismatched-prepared-operation'),
      prepare: (_) async => WriteIntent(
        intentId: 'wrong-domain-intent',
        operation: WriteOperation.bykcSelectCourse,
        targetSummary: '不可信的异领域意图',
        resolvedRoute: ConnectionMode.direct,
        warnings: const <String>[],
        expiresAt: DateTime.now().add(const Duration(minutes: 2)),
        requestDigest: 'digest',
      ),
      picker: _validYgdkPhoto,
      commit: (_) async {
        commitCalls++;
        return const WriteCommitResult(
          operation: WriteOperation.bykcSelectCourse,
          success: true,
          message: '不应提交',
          outcomeUnknown: false,
        );
      },
      discard: (intentId) async => discardedIntentIds.add(intentId),
      refresh: ({required expectedRoute}) async {},
    );

    await _openAndFillYgdkForm(tester);
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();

    expect(discardedIntentIds, const <String>['wrong-domain-intent']);
    expect(commitCalls, 0);
    expect(find.text('确认提交'), findsNothing);
    expect(find.text('暂时无法准备阳光打卡；尚未提交任何写请求。'), findsOneWidget);
  });

  testWidgets('阳光打卡回读能力在提交期间丢失时不虚称已尝试', (tester) async {
    final readbackAvailable = ValueNotifier<bool>(true);
    final commitResult = Completer<WriteCommitResult>();
    addTearDown(readbackAvailable.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: ValueListenableBuilder<bool>(
          valueListenable: readbackAvailable,
          builder: (context, available, _) => coordinatedShell(
            user: const UserSummary(username: 'student'),
            snapshots: _ygdkSnapshots(),
            routePolicy: RoutePolicy.auto,
            telemetryEnabled: false,
            onRefresh: () async {},
            onRetryFeature: (_) async {},
            onPrepareYgdkSubmitWrite: (_) async => _validYgdkIntent(),
            onPickYgdkPhoto: _validYgdkPhoto,
            onCommitWrite: (_) => commitResult.future,
            onRefreshYgdkAfterWrite: available
                ? ({required expectedRoute}) async {}
                : null,
            onDiscardWriteIntent: (_) async {},
            onLogout: () async {},
            onLogoutAndClearAccount: () async {},
            onRoutePolicyChanged: (_) {},
            onTelemetryChanged: (_) {},
          ),
        ),
      ),
    );

    await _openAndFillYgdkForm(tester);
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pump();
    readbackAvailable.value = false;
    await tester.pump();
    commitResult.complete(
      const WriteCommitResult(
        operation: WriteOperation.ygdkSubmit,
        success: true,
        message: '阳光打卡已提交',
        outcomeUnknown: false,
        resolvedRoute: ConnectionMode.direct,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('已尝试'), findsNothing);
    expect(find.textContaining('请手动刷新概览与记录'), findsOneWidget);
  });

  testWidgets('阳光打卡真实抛出 OutcomeUnknown 时只按原路线回读一次', (tester) async {
    var refreshCalls = 0;
    ConnectionMode? refreshedRoute;
    await _pumpYgdkShell(
      tester,
      key: const ValueKey<String>('thrown-outcome-unknown'),
      prepare: (_) async => _validYgdkIntent(route: ConnectionMode.webvpn),
      picker: _validYgdkPhoto,
      commit: (_) async => throw const UiError(
        code: UbaaErrorCode.outcomeUnknown,
        title: '提交结果不确定',
        message: '不得展示的上游错误',
        retryable: false,
      ),
      discard: (_) async {},
      refresh: ({required expectedRoute}) async {
        refreshCalls++;
        refreshedRoute = expectedRoute;
      },
    );

    await _openAndFillYgdkForm(tester);
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(refreshCalls, 1);
    expect(refreshedRoute, ConnectionMode.webvpn);
    expect(find.text('提交结果不确定；已尝试按原路线刷新概览与记录，请勿重复提交。'), findsOneWidget);
    expect(find.textContaining('已核对'), findsNothing);
  });

  testWidgets('阳光打卡 commit 结果操作错配时按原 intent 收敛为结果不确定', (tester) async {
    var refreshCalls = 0;
    ConnectionMode? refreshedRoute;
    await _pumpYgdkShell(
      tester,
      key: const ValueKey<String>('mismatched-operation'),
      prepare: (_) async => _validYgdkIntent(route: ConnectionMode.webvpn),
      picker: _validYgdkPhoto,
      commit: (_) async => const WriteCommitResult(
        operation: WriteOperation.bykcSelectCourse,
        success: true,
        message: '不可信的异领域成功',
        outcomeUnknown: false,
      ),
      discard: (_) async {},
      refresh: ({required expectedRoute}) async {
        refreshCalls++;
        refreshedRoute = expectedRoute;
      },
    );

    await _openAndFillYgdkForm(tester);
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(refreshCalls, 1);
    expect(refreshedRoute, ConnectionMode.webvpn);
    expect(find.text('提交结果不确定；已尝试按原路线刷新概览与记录，请勿重复提交。'), findsOneWidget);
    expect(find.textContaining('不可信的异领域成功'), findsNothing);
  });

  testWidgets('阳光打卡照片上传不可用时明确不自动重试且未最终提交', (tester) async {
    await _pumpYgdkShell(
      tester,
      key: const ValueKey<String>('upload-unavailable'),
      prepare: (_) async => _validYgdkIntent(),
      picker: _validYgdkPhoto,
      commit: (_) async => throw const UiError(
        code: UbaaErrorCode.upstreamUnavailable,
        title: '学校服务暂时不可用',
        message: '请稍后重试；其他功能可能仍然可以使用。',
        actionLabel: '重试',
        retryable: true,
      ),
      discard: (_) async {},
      refresh: ({required expectedRoute}) async {},
    );

    await _openAndFillYgdkForm(tester);
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(find.text('照片上传未完成，应用不会自动重试；本次阳光打卡尚未最终提交。'), findsOneWidget);
    expect(find.textContaining('请稍后重试'), findsNothing);
  });

  testWidgets('阳光打卡表单不洗白时间文件名或 MIME 原始输入', (tester) async {
    YgdkSubmitInput? preparedInput;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: _ygdkSnapshots(),
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareYgdkSubmitWrite: (input) async {
            preparedInput = input;
            return WriteIntent(
              intentId: 'ygdk-raw-input',
              operation: WriteOperation.ygdkSubmit,
              targetSummary: '阳光打卡',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>[],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest',
            );
          },
          onPickYgdkPhoto: () async => const YgdkPhotoInput(
            bytes: <int>[1, 2, 3],
            fileName: ' photo.png ',
            mimeType: ' IMAGE/PNG ',
          ),
          onCommitWrite: (_) async => throw StateError('不应 commit'),
          onRefreshYgdkAfterWrite: ({required expectedRoute}) async {},
          onDiscardWriteIntent: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );

    await _openAndFillYgdkForm(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), ' 2026-09-01 08:00 ');
    await tester.enterText(fields.at(2), ' 2026-09-01 09:00 ');
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();

    expect(preparedInput?.startTime, ' 2026-09-01 08:00 ');
    expect(preparedInput?.endTime, ' 2026-09-01 09:00 ');
    expect(preparedInput?.photo.fileName, ' photo.png ');
    expect(preparedInput?.photo.mimeType, ' IMAGE/PNG ');
  });

  testWidgets('OutcomeUnknown 打卡只按原路线刷新且绝不升级为已核对', (tester) async {
    ConnectionMode? refreshedRoute;
    var refreshCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: _ygdkSnapshots(),
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareYgdkSubmitWrite: (_) async => WriteIntent(
            intentId: 'ygdk-unknown',
            operation: WriteOperation.ygdkSubmit,
            targetSummary: '阳光打卡',
            resolvedRoute: ConnectionMode.webvpn,
            warnings: const <String>[],
            expiresAt: DateTime.now().add(const Duration(minutes: 2)),
            requestDigest: 'digest',
          ),
          onPickYgdkPhoto: _validYgdkPhoto,
          onCommitWrite: (_) async => const WriteCommitResult(
            operation: WriteOperation.ygdkSubmit,
            success: false,
            message: '不应展示的成功文案',
            outcomeUnknown: true,
            resolvedRoute: ConnectionMode.webvpn,
            // 防御性用例：即使边界误带收据，unknown 也不得用它核对。
            ygdkReceipt: YgdkSubmitReceipt(recordId: 41),
          ),
          onRefreshYgdkAfterWrite: ({required expectedRoute}) async {
            refreshCalls++;
            refreshedRoute = expectedRoute;
          },
          onDiscardWriteIntent: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );

    await _openAndFillYgdkForm(tester);
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(refreshCalls, 1);
    expect(refreshedRoute, ConnectionMode.webvpn);
    expect(find.text('提交结果不确定；已尝试按原路线刷新概览与记录，请勿重复提交。'), findsOneWidget);
    expect(find.textContaining('已核对'), findsNothing);
  });

  testWidgets('取消阳光打卡表单后释放照片预览引用', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: coordinatedShell(
          user: const UserSummary(username: 'student'),
          snapshots: _ygdkSnapshots(),
          routePolicy: RoutePolicy.auto,
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onPrepareYgdkSubmitWrite: (_) async => throw StateError('不应 prepare'),
          onPickYgdkPhoto: _validYgdkPhoto,
          onCommitWrite: (_) async => throw StateError('不应 commit'),
          onRefreshYgdkAfterWrite: ({required expectedRoute}) async {},
          onDiscardWriteIntent: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );

    await _openAndFillYgdkForm(tester);
    expect(
      find.byKey(const ValueKey<String>('ygdk-photo-preview')),
      findsOneWidget,
    );
    final preview = tester.widget<Image>(
      find.byKey(const ValueKey<String>('ygdk-photo-preview')),
    );
    expect(preview.image, isA<ResizeImage>());
    final resizedPreview = preview.image as ResizeImage;
    expect(resizedPreview.width, 720);
    expect(resizedPreview.height, 480);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('ygdk-photo-preview')),
      findsNothing,
    );

    await tester.tap(find.text('准备阳光打卡'));
    await tester.pumpAndSettle();
    expect(find.text('选择照片'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('ygdk-photo-preview')),
      findsNothing,
    );
  });
}

Map<FeatureId, FeatureSnapshot> _ygdkSnapshots() =>
    <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.ygdk
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '跑步项目',
                    actions: <FeatureAction>[
                      YgdkSubmitAction(
                        classifyId: 31,
                        itemId: 7,
                        eligibility: ActionEligibility.allowed,
                      ),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };

Future<YgdkPhotoInput> _validYgdkPhoto() async => YgdkPhotoInput(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
    'AAAADUlEQVQIHWP4z8DwHwAFgAI/ScLZYQAAAABJRU5ErkJggg==',
  ),
  fileName: 'photo.png',
  mimeType: 'image/png',
);

WriteIntent _validYgdkIntent({ConnectionMode route = ConnectionMode.direct}) =>
    WriteIntent(
      intentId: 'ygdk-intent',
      operation: WriteOperation.ygdkSubmit,
      targetSummary: '阳光打卡',
      resolvedRoute: route,
      warnings: const <String>[],
      expiresAt: DateTime.now().add(const Duration(minutes: 2)),
      requestDigest: 'digest',
    );

Future<void> _pumpYgdkShell(
  WidgetTester tester, {
  required Key key,
  YgdkSubmitPreparer? prepare,
  YgdkPhotoPicker? picker,
  Future<WriteCommitResult> Function(String intentId)? commit,
  WriteIntentDiscarder? discard,
  YgdkSubmissionRefresher? refresh,
}) => tester.pumpWidget(
  MaterialApp(
    theme: UbaaTheme.light(),
    home: coordinatedShell(
      key: key,
      user: const UserSummary(username: 'student'),
      snapshots: _ygdkSnapshots(),
      routePolicy: RoutePolicy.auto,
      telemetryEnabled: false,
      onRefresh: () async {},
      onRetryFeature: (_) async {},
      onPrepareYgdkSubmitWrite: prepare,
      onPickYgdkPhoto: picker,
      onCommitWrite: commit,
      onRefreshYgdkAfterWrite: refresh,
      onDiscardWriteIntent: discard,
      onLogout: () async {},
      onLogoutAndClearAccount: () async {},
      onRoutePolicyChanged: (_) {},
      onTelemetryChanged: (_) {},
    ),
  ),
);

Future<void> _openYgdkDetails(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('阳光打卡'));
  await tester.pumpAndSettle();
}

Future<void> _openAndFillYgdkForm(WidgetTester tester) async {
  await _openYgdkDetails(tester);
  await tester.tap(find.text('准备阳光打卡'));
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(1), '2026-09-01 08:00');
  await tester.enterText(fields.at(2), '2026-09-01 09:00');
  await tester.tap(find.text('选择照片'));
  await tester.pumpAndSettle();
}
