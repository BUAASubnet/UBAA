part of '../widgets_test.dart';

void _registerFeatureRenderingTests() {
  testWidgets('功能卡片打开真实详情字段而不是占位页', (tester) async {
    var clearedAccount = false;
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          resolvedRoute: feature == FeatureId.schedule
              ? ConnectionMode.direct
              : null,
          details: feature == FeatureId.schedule
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '高等数学',
                    subtitle: '周一 08:00',
                    fields: <FeatureField>[
                      FeatureField(label: '地点', value: '主楼 101'),
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
          activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async => clearedAccount = true,
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('主楼 101'), findsOneWidget);
    expect(find.text('实际路线：直连'), findsOneWidget);
    expect(find.textContaining('只读详情页面将在'), findsNothing);

    await tester.tap(find.text('返回功能列表'));
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('直连'), findsOneWidget);
    await tester.tap(find.text('退出并清除本机账号'));
    await tester.pumpAndSettle();
    expect(find.text('清除本机账号？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(clearedAccount, isFalse);
    await tester.tap(find.text('退出并清除本机账号'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退出并清除'));
    await tester.pumpAndSettle();
    expect(clearedAccount, isTrue);
  });
}

void _registerFeatureInputTests() {
  testWidgets('场馆可预约时段先填写 typed 信息再进入确认页', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.cgyy
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '讨论室 上午',
                    fields: <FeatureField>[
                      FeatureField(label: '站点 ID', value: '3'),
                      FeatureField(label: '日期', value: '2026-09-03'),
                      FeatureField(label: '空间 ID', value: '4'),
                      FeatureField(label: '空间组 ID', value: '9'),
                      FeatureField(label: '时段 ID', value: '5'),
                      FeatureField(label: '可预约', value: '是'),
                    ],
                  ),
                  FeatureDetail(
                    title: '讨论室 下午',
                    fields: <FeatureField>[
                      FeatureField(label: '站点 ID', value: '3'),
                      FeatureField(label: '日期', value: '2026-09-03'),
                      FeatureField(label: '空间 ID', value: '4'),
                      FeatureField(label: '空间组 ID', value: '9'),
                      FeatureField(label: '时段 ID', value: '6'),
                      FeatureField(label: '可预约', value: '是'),
                    ],
                  ),
                  FeatureDetail(
                    title: '另一空间',
                    fields: <FeatureField>[
                      FeatureField(label: '站点 ID', value: '3'),
                      FeatureField(label: '日期', value: '2026-09-03'),
                      FeatureField(label: '空间 ID', value: '5'),
                      FeatureField(label: '空间组 ID', value: '9'),
                      FeatureField(label: '时段 ID', value: '7'),
                      FeatureField(label: '可预约', value: '是'),
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
          onPrepareCgyySubmitWrite: (input) async {
            prepareCalls++;
            expect(input.venueSiteId, 3);
            expect(input.reservationDate, '2026-09-03');
            expect(
              input.selections.map((selection) => selection.spaceId),
              <int>[4, 4],
            );
            expect(input.selections.map((selection) => selection.timeId), <int>[
              5,
              6,
            ]);
            expect(input.phone, 'phone-placeholder');
            expect(input.purposeType, 2);
            return WriteIntent(
              intentId: 'cgyy-reserve-1',
              operation: WriteOperation.cgyySubmitReservation,
              targetSummary: '提交场馆预约',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>['如需验证码，材料只在本次操作内使用'],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest',
            );
          },
          onCommitWrite: (intentId) async {
            commitCalls++;
            expect(intentId, 'cgyy-reserve-1');
            return const WriteCommitResult(
              operation: WriteOperation.cgyySubmitReservation,
              success: true,
              message: '场馆预约结果已提交，请刷新订单确认',
              outcomeUnknown: false,
              cgyyReceipt: CgyyReservationReceipt(
                orderId: 42,
                venueSiteId: 3,
                reservationDate: '2026-09-03',
                orderStatus: 1,
              ),
            );
          },
          onVerifyCgyyReceipt: (receipt) async {
            expect(receipt.orderId, 42);
            return true;
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
    await tester.tap(find.text('准备场馆预约').first);
    await tester.pumpAndSettle();
    expect(find.text('选择预约时段（已选 1 个）'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '空间 5 · 时段 7'), findsNothing);
    await tester.tap(find.widgetWithText(FilterChip, '空间 4 · 时段 6'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'phone-placeholder');
    await tester.enterText(fields.at(2), '课程讨论');
    await tester.enterText(fields.at(3), '2');
    await tester.enterText(fields.at(4), '3');
    await tester.enterText(fields.at(5), '讨论');
    await tester.enterText(fields.at(6), '张三');
    await tester.tap(find.text('继续确认'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认场馆预约'), findsNWidgets(2));
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(find.text('场馆预约结果已提交，请刷新订单确认（订单编号 42，订单列表已核对）'), findsOneWidget);
  });

  testWidgets('阳光打卡填写时间并选择内存照片后才进入确认页', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.ygdk
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '跑步项目',
                    fields: <FeatureField>[
                      FeatureField(label: '项目编号', value: '7'),
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
          onPrepareYgdkSubmitWrite: (input) async {
            prepareCalls++;
            expect(input.itemId, 7);
            expect(input.startTime, '2026-09-01 08:00');
            expect(input.endTime, '2026-09-01 09:00');
            expect(input.photo?.fileName, 'photo-placeholder.jpg');
            return WriteIntent(
              intentId: 'ygdk-1',
              operation: WriteOperation.ygdkSubmit,
              targetSummary: '提交阳光打卡',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>['提交后请刷新记录确认'],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'ygdk-digest',
            );
          },
          onPickYgdkPhoto: () async => const YgdkPhotoInput(
            bytes: <int>[1, 2, 3],
            fileName: 'photo-placeholder.jpg',
            mimeType: 'image/jpeg',
          ),
          onCommitWrite: (intentId) async {
            commitCalls++;
            expect(intentId, 'ygdk-1');
            return const WriteCommitResult(
              operation: WriteOperation.ygdkSubmit,
              success: true,
              message: '阳光打卡结果已提交，请刷新记录确认',
              outcomeUnknown: false,
              resolvedRoute: ConnectionMode.direct,
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
    await tester.tap(find.text('阳光打卡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备阳光打卡'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '2026-09-01 08:00');
    await tester.enterText(fields.at(2), '2026-09-01 09:00');
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();
    expect(find.text('已选择照片：photo-placeholder.jpg'), findsOneWidget);
    await tester.tap(find.text('继续确认'));
    await tester.pump(const Duration(milliseconds: 700));
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认阳光打卡'), findsNWidgets(2));
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(find.text('阳光打卡结果已提交，请刷新记录确认'), findsOneWidget);
  });

  testWidgets('图书馆可预约座位展示完整时段摘要后再准备写入', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.libbook
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '座位 A-01',
                    fields: <FeatureField>[
                      FeatureField(label: '分区 ID', value: 'area-1'),
                      FeatureField(label: '座位 ID', value: 'seat-2'),
                      FeatureField(label: '日期', value: '2026-09-02'),
                      FeatureField(label: '时段', value: '3'),
                      FeatureField(label: '开始时间', value: '10:00'),
                      FeatureField(label: '结束时间', value: '12:00'),
                      FeatureField(label: '可预约', value: '是'),
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
          onPrepareLibbookReserveWrite:
              ({
                required areaId,
                required seatId,
                required day,
                required segment,
                required startTime,
                required endTime,
              }) async {
                prepareCalls++;
                expect(areaId, 'area-1');
                expect(seatId, 'seat-2');
                expect(day, '2026-09-02');
                expect(segment, '3');
                expect(startTime, '10:00');
                expect(endTime, '12:00');
                return WriteIntent(
                  intentId: 'reserve-seat-2',
                  operation: WriteOperation.libbookReserve,
                  targetSummary: 'area-1 / seat-2 / 2026-09-02 3',
                  resolvedRoute: ConnectionMode.direct,
                  warnings: const <String>['请确认座位、日期和时段'],
                  expiresAt: DateTime.now().add(const Duration(minutes: 2)),
                  requestDigest: 'digest',
                );
              },
          onCommitWrite: (intentId) async {
            commitCalls++;
            expect(intentId, 'reserve-seat-2');
            return const WriteCommitResult(
              operation: WriteOperation.libbookReserve,
              success: true,
              message: '预约结果已提交，请刷新预约记录确认',
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
    await tester.tap(find.byIcon(Icons.apps_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('图书馆座位'));
    await tester.tap(find.text('图书馆座位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('准备预约此座位'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认图书馆预约'), findsNWidgets(2));
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(find.text('预约结果已提交，请刷新预约记录确认'), findsOneWidget);
  });
}

void _registerFeatureCollectionTests() {
  testWidgets('长详情列表分页且筛选会回到第一页', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.schedule
              ? List<FeatureDetail>.generate(
                  21,
                  (index) => FeatureDetail(title: '课程 ${index + 1}'),
                )
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
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('课程 21'), findsNothing);
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('课程 21'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '课程 1');
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsNothing);
    expect(find.text('课程 1'), findsNWidgets(2));
  });

  testWidgets('超长详情列表只保留当前分页避免页面节点累积', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.schedule
              ? List<FeatureDetail>.generate(
                  1000,
                  (index) => FeatureDetail(title: '长列表课程 ${index + 1}'),
                )
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
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 50'), findsOneWidget);
    expect(find.text('长列表课程 1'), findsOneWidget);
    expect(find.text('长列表课程 21'), findsNothing);
    for (var page = 2; page <= 6; page++) {
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('$page / 50'), findsOneWidget);
      expect(find.text('长列表课程 ${(page - 1) * 20 + 1}'), findsOneWidget);
      expect(find.text('长列表课程 ${(page - 2) * 20 + 1}'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('服务端分页使用 Core 元数据并通过 typed 查询翻页', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[FeatureDetail(title: '第一页课程')]
              : const <FeatureDetail>[],
          pagination: feature == FeatureId.bykc
              ? const FeaturePagination(
                  page: 1,
                  size: 20,
                  total: 41,
                  totalPages: 3,
                  hasMore: true,
                )
              : null,
        ),
    };
    FeatureQuery? received;
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
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.bykc);
            received = query;
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
    expect(find.text('第 1 / 3 页（共 41 条）'), findsOneWidget);
    await tester.tap(find.byTooltip('下一页').last);
    await tester.pumpAndSettle();
    expect(received?.page, 2);
  });

  testWidgets('领域查询控件提交日期和校区 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.classroom
              ? const <FeatureDetail>[FeatureDetail(title: '主楼 101')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
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
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.classroom);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('空教室查询'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2026-09-02');
    await tester.tap(find.text('校区 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校区 2'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('应用筛选'));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.date, DateTime(2026, 9, 2));
    expect(received?.campus, 2);
  });

  testWidgets('日期控件拒绝非日期字符串和不存在的日历日期', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.classroom
              ? const <FeatureDetail>[FeatureDetail(title: '主楼 101')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
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
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.classroom);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('空教室查询'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      '2026-09-02T12:00:00+08:00',
    );
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();

    expect(received, isNull);
    expect(find.text('日期格式无效，请使用 YYYY-MM-DD。'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '2026-02-30');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received, isNull);
  });

  testWidgets('空教室查询控件提交楼层和节次本地筛选参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.classroom
              ? const <FeatureDetail>[FeatureDetail(title: '主楼 101')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? received;
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
          onFeatureQuery: (feature, query) async {
            expect(feature, FeatureId.classroom);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('空教室查询'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), 'F2');
    await tester.enterText(fields.at(2), '3');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.floorId, 'F2');
    expect(received?.section, '3');
  });

  testWidgets('查询失败重试会复用当前 typed 查询而不是退回摘要', (tester) async {
    var snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.classroom
              ? const <FeatureDetail>[FeatureDetail(title: '主楼 101')]
              : const <FeatureDetail>[],
        ),
    };
    FeatureQuery? applied;
    var retryCalls = 0;
    Future<void> onQuery(FeatureId feature, FeatureQuery query) async {
      expect(feature, FeatureId.classroom);
      applied = query;
    }

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
          onFeatureQuery: onQuery,
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('空教室查询'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'F2');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(applied?.floorId, 'F2');

    snapshots = {
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: feature == FeatureId.classroom
              ? FeatureLoadStatus.failure
              : FeatureLoadStatus.success,
          summary: '已加载',
          error: feature == FeatureId.classroom
              ? const UiError(
                  code: UbaaErrorCode.networkError,
                  title: '网络错误',
                  message: '请稍后重试',
                  retryable: true,
                )
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
          telemetryEnabled: false,
          onRefresh: () async {},
          onRetryFeature: (_) async => retryCalls++,
          onFeatureQuery: onQuery,
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(retryCalls, 0);
    expect(applied?.floorId, 'F2');
  });
}
