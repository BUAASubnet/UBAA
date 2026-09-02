import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('主页和详情页保持稳定视觉基线', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '样例数据已加载',
          details: <FeatureDetail>[
            FeatureDetail(
              title: '样例${feature.title}',
              subtitle: '无签名测试数据',
              fields: const <FeatureField>[
                FeatureField(label: '状态', value: '可查看'),
              ],
            ),
          ],
          resolvedRoute: ConnectionMode.direct,
        ),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaMainShell(
          user: const UserSummary(username: 'student', displayName: '测试同学'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.auto,
          activeRoutes: const <ConnectionMode>[ConnectionMode.direct],
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
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(UbaaMainShell),
      matchesGoldenFile('goldens/main_shell_light.png'),
    );

    await tester.tap(find.text('课表查询'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(UbaaMainShell),
      matchesGoldenFile('goldens/feature_detail_light.png'),
    );
  });

  testWidgets('启动页展示品牌且登录页不猜测验证码流程', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: UbaaTheme.light(), home: const UbaaSplashView()),
    );

    expect(find.text('UBAA'), findsOneWidget);
    expect(find.text('Make BUAA Great Again'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: UbaaTheme.light(),
        home: UbaaLoginView(
          username: '',
          password: '',
          captcha: '',
          rememberPassword: false,
          autoLogin: false,
          routePolicy: RoutePolicy.auto,
          error: null,
          isLoading: false,
          credentialPersistenceAvailable: false,
          onUsernameChanged: (_) {},
          onPasswordChanged: (_) {},
          onCaptchaChanged: (_) {},
          onRememberPasswordChanged: (_) {},
          onAutoLoginChanged: (_) {},
          onRoutePolicyChanged: (_) {},
          onSubmit: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('UBAA 登录'), findsOneWidget);
    expect(find.text('验证码'), findsNothing);
    expect(find.textContaining('安全存储'), findsOneWidget);
  });

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
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    var deselectCalls = 0;
    var signCalls = 0;
    var commitCalls = 0;
    var refreshCalls = 0;
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
          onPrepareBykcSignWrite: (courseId, signType) async {
            signCalls++;
            expect(courseId, 42);
            expect(signType, 1);
            return signIntent;
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
          onWriteSuccess: (operation) async {
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
    expect(commitCalls, 0);
    expect(find.text('确认博雅签到'), findsNWidgets(2));
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

  testWidgets('课堂签到从公开课程编号准备并在确认后提交', (tester) async {
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
                      FeatureField(label: '课程 ID', value: 'course-7'),
                      FeatureField(label: '签到状态', value: '未签到'),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var prepareCalls = 0;
    var commitCalls = 0;
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
          onPrepareSigninWrite: (courseId) async {
            prepareCalls++;
            expect(courseId, 'course-7');
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
    expect(find.text('签到结果已提交，请刷新确认'), findsOneWidget);
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

  testWidgets('博雅课程状态收紧选课和退选入口', (tester) async {
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
                      FeatureField(label: '课程 ID', value: '42'),
                      FeatureField(label: '状态', value: 'selected'),
                      FeatureField(label: '已选', value: '是'),
                    ],
                  ),
                ]
              : const <FeatureDetail>[],
        ),
    };
    var selectCalls = 0;
    var deselectCalls = 0;
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
    expect(selectCalls, 0);
    expect(deselectCalls, 0);
  });

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
                      FeatureField(label: '订单状态', value: '待审核'),
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

  testWidgets('图书馆预约取消只从公开预约 ID 进入确认页', (tester) async {
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
                    title: '图书馆预约',
                    fields: <FeatureField>[
                      FeatureField(label: '预约 ID', value: 'booking-7'),
                      FeatureField(label: '状态', value: '有效'),
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
            expect(operation, WriteOperation.libbookCancelBooking);
            expect(targetId, 'booking-7');
            return WriteIntent(
              intentId: 'cancel-booking-7',
              operation: operation,
              targetSummary: '取消图书馆预约 booking-7',
              resolvedRoute: ConnectionMode.direct,
              warnings: const <String>['取消后请刷新预约记录确认状态'],
              expiresAt: DateTime.now().add(const Duration(minutes: 2)),
              requestDigest: 'digest',
            );
          },
          onCommitWrite: (intentId) async {
            commitCalls++;
            expect(intentId, 'cancel-booking-7');
            return const WriteCommitResult(
              operation: WriteOperation.libbookCancelBooking,
              success: true,
              message: '预约取消结果已提交，请刷新确认',
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
    await tester.tap(find.text('准备取消预约'));
    await tester.pumpAndSettle();
    expect(prepareCalls, 1);
    expect(commitCalls, 0);
    expect(find.text('确认取消图书馆预约'), findsNWidgets(2));
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(commitCalls, 1);
    expect(find.text('预约取消结果已提交，请刷新确认'), findsOneWidget);
  });

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

  testWidgets('课堂签到控件提交未签到本地派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.signin
              ? const <FeatureDetail>[FeatureDetail(title: '签到课程')]
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
            expect(feature, FeatureId.signin);
            received = query;
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
    await tester.tap(find.text('全部课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未签到'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.signinPending);
  });

  testWidgets('课堂签到已完成时禁用重复签到入口', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.signin
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '已完成签到课程',
                    fields: <FeatureField>[
                      FeatureField(label: '课程 ID', value: 'course-done'),
                      FeatureField(label: '签到状态', value: '已签到'),
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
          onPrepareSigninWrite: (_) async {
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
    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课堂签到'));
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '准备签到'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('该课程已签到，不能重复提交。'), findsOneWidget);
    expect(prepareCalls, 0);
  });

  testWidgets('考试查询控件提交已安排本地派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.exam
              ? const <FeatureDetail>[FeatureDetail(title: '考试')]
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
            expect(feature, FeatureId.exam);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('考试查询'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部考试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已安排'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.examArranged);
  });

  testWidgets('成绩查询控件提交已出成绩本地派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.grades
              ? const <FeatureDetail>[FeatureDetail(title: '成绩')]
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
            expect(feature, FeatureId.grades);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.tap(find.text('成绩查询'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部成绩'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已出成绩'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.gradesScored);
  });

  testWidgets('博雅查询控件提交课程详情 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[FeatureDetail(title: '课程')]
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
    await tester.scrollUntilVisible(
      find.text('博雅课程'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('博雅课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程详情'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '12345');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.bykcDetail);
    expect(received?.courseId, '12345');
  });

  testWidgets('博雅查询控件提交修读统计视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[FeatureDetail(title: '课程')]
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
    await tester.scrollUntilVisible(
      find.text('博雅课程'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('博雅课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('修读统计'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.bykcStatistics);
  });

  testWidgets('课表查询控件提交学期和周次 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.schedule
              ? const <FeatureDetail>[FeatureDetail(title: '高等数学')]
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
            expect(feature, FeatureId.schedule);
            received = query;
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
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '2026-2027-1');
    await tester.enterText(fields.at(1), '3');
    await tester.ensureVisible(find.text('应用筛选'));
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.term, '2026-2027-1');
    expect(received?.week, 3);
  });

  testWidgets('课表查询控件提交学期列表视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.schedule
              ? const <FeatureDetail>[FeatureDetail(title: '课表')]
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
            expect(feature, FeatureId.schedule);
            received = query;
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
    await tester.tap(find.text('今日课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('学期列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.scheduleTerms);
  });

  testWidgets('博雅查询控件提交 1-based 分页参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.bykc
              ? const <FeatureDetail>[FeatureDetail(title: '课程')]
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
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '2');
    await tester.enterText(fields.at(1), '50');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.page, 2);
    expect(received?.size, 50);
  });

  testWidgets('图书馆查询控件提交分区和时段 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.libbook
              ? const <FeatureDetail>[FeatureDetail(title: '图书馆')]
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
            expect(feature, FeatureId.libbook);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('图书馆座位'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('图书馆座位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('馆列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('馆区列表'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'main-library');
    await tester.enterText(fields.at(1), 'floor-1');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.libbookAreas);
    expect(received?.premisesId, 'main-library');
    expect(received?.storeyId, 'floor-1');
  });

  testWidgets('阳光打卡查询控件提交记录分页 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.ygdk
              ? const <FeatureDetail>[FeatureDetail(title: '打卡概览')]
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
            expect(feature, FeatureId.ygdk);
            received = query;
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
    await tester.tap(find.text('概览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录列表'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '3');
    await tester.enterText(fields.at(1), '15');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.ygdkRecords);
    expect(received?.page, 3);
    expect(received?.size, 15);
  });

  testWidgets('场馆查询控件提交日期空间 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.cgyy
              ? const <FeatureDetail>[FeatureDetail(title: '场馆')]
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
            expect(feature, FeatureId.cgyy);
            received = query;
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
    await tester.scrollUntilVisible(
      find.text('场馆预约'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('场馆预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('站点列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日期空间'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, '17');
    await tester.enterText(fields.at(1), '2026-09-03');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.cgyyDayInfo);
    expect(received?.siteId, 17);
    expect(received?.date, DateTime(2026, 9, 3));
  });

  testWidgets('评教查询控件提交待评本地派生视图', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.evaluation
              ? const <FeatureDetail>[FeatureDetail(title: '评教')]
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
            expect(feature, FeatureId.evaluation);
            received = query;
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
    await tester.scrollUntilVisible(
      find.text('教学评教'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('教学评教'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('待评课程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.evaluationPending);
  });

  testWidgets('SPOC 查询控件提交作业详情 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.spoc
              ? const <FeatureDetail>[
                  FeatureDetail(
                    title: '作业',
                    fields: <FeatureField>[
                      FeatureField(label: '作业编号', value: 'assignment-17'),
                    ],
                  ),
                ]
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
            expect(feature, FeatureId.spoc);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('SPOC作业'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('SPOC作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业详情'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('assignment-17').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.spocDetail);
    expect(received?.assignmentId, 'assignment-17');
  });

  testWidgets('希冀查询控件提交作业详情 typed 参数', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.judge
              ? const <FeatureDetail>[FeatureDetail(title: '作业')]
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
            expect(feature, FeatureId.judge);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('希冀作业'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('希冀作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业详情'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.first, 'course-3');
    await tester.enterText(fields.at(1), 'assignment-17');
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.judgeDetail);
    expect(received?.courseId, 'course-3');
    expect(received?.assignmentId, 'assignment-17');
    expect(received?.includeExpired, isFalse);
  });

  testWidgets('希冀查询控件可包含已过期作业', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.judge
              ? const <FeatureDetail>[FeatureDetail(title: '作业')]
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
            expect(feature, FeatureId.judge);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('希冀作业'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('希冀作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('包含已过期作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.includeExpired, isTrue);
  });

  testWidgets('希冀查询控件提交批量作业详情 typed 键', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: FeatureLoadStatus.success,
          summary: '已加载',
          details: feature == FeatureId.judge
              ? const <FeatureDetail>[FeatureDetail(title: '作业')]
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
            expect(feature, FeatureId.judge);
            received = query;
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('希冀作业'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('希冀作业'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('作业列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量详情'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'course-2/assignment-2\ncourse-1/assignment-1',
    );
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(received?.view, FeatureQueryView.judgeBatchDetails);
    expect(received?.judgeKeys, const <JudgeAssignmentQueryKey>[
      JudgeAssignmentQueryKey(
        courseId: 'course-2',
        assignmentId: 'assignment-2',
      ),
      JudgeAssignmentQueryKey(
        courseId: 'course-1',
        assignmentId: 'assignment-1',
      ),
    ]);
  });

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
                ? const <FeatureDetail>[
                    FeatureDetail(title: '上次成功详情'),
                  ]
                : const <FeatureDetail>[],
            error: status == FeatureLoadStatus.failure ||
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

  testWidgets('功能卡片暴露包含状态和操作提示的无障碍语义', (tester) async {
    final snapshots = <FeatureId, FeatureSnapshot>{
      for (final feature in FeatureId.values)
        feature: FeatureSnapshot(
          feature: feature,
          status: feature == FeatureId.schedule
              ? FeatureLoadStatus.success
              : FeatureLoadStatus.idle,
          summary: feature == FeatureId.schedule ? '今日课程' : null,
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
          onRetryFeature: (_) async {},
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
          onTelemetryChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('课表查询：今日课程。点击查看详情'),
      findsOneWidget,
    );
  });
}
