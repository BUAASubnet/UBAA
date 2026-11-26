import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/coursework/signin_qr_sheet.dart';
import '../../support/home_harness.dart';
import '../../support/write_harness.dart';

final _button = find.widgetWithText(FilledButton, '上课');
final _sheet = find.byType(SigninQrSheet);
final _inWindow = Clock.fixed(DateTime.utc(2026, 10, 26, 7));
const _qr = 'https://example.invalid/signin';

void main() {
  testWidgets('首页已签到课程只在窗口内提供二维码，打开后不轮询', (tester) async {
    var now = DateTime.utc(2026, 10, 26, 5, 49);
    await withClock(Clock(() => now), () async {
      final state = await mount(tester, signed: true, check: (_) async => true);
      final button = find.widgetWithText(FilledButton, '二维码');
      expect(button, findsNothing);
      now = DateTime.utc(2026, 10, 26, 5, 50);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.text('已签到'), findsOneWidget);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(_sheet, findsOneWidget);
      expect(state.qrTargets, everyElement('canonical-1'));
      expect(state.qrTargets, hasLength(2));
      expect(state.statusTargets, isEmpty);
      await tester.binding.handlePopRoute();
      now = DateTime.utc(2026, 10, 26, 9, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(button, findsNothing);
    });
  });

  testWidgets('首页点击上课直接打开二维码且不调用写入', (tester) async {
    await withClock(_inWindow, () async {
      final state = await mount(tester);
      await tester.tap(_button.first);
      await tester.pump();
      expect(state.prepares, 0);
      expect(state.commits, 0);
      expect(_sheet, findsOneWidget);
      expect(state.qrTargets, ['canonical-1']);
    });
  });

  testWidgets('首页待办随分钟刷新启用二维码按钮，下课后保留未签到', (tester) async {
    var now = DateTime.utc(2026, 10, 26, 5, 49);
    await withClock(Clock(() => now), () async {
      final state = await mount(tester);
      expect(tester.widget<FilledButton>(_button.first).onPressed, isNull);
      expect(find.text('上课前 10 分钟开放'), findsNWidgets(2));
      await tester.tap(find.text('课程1'));
      expect(state.qrTargets, isEmpty);

      now = DateTime.utc(2026, 10, 26, 5, 50);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(_button.first).onPressed, isNotNull);
      expect(find.text('上课前 10 分钟开放'), findsNothing);

      now = DateTime.utc(2026, 10, 26, 9, 1);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(_button, findsNothing);
      expect(find.text('未签到'), findsNWidgets(2));
    });
  });

  testWidgets('午夜后尚未触发分钟刷新时点击旧上课只刷新，不打开二维码', (tester) async {
    var now = DateTime.parse('2026-03-24T23:59:55+08:00');
    var qrFetches = 0, refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHarness(
            user: null,
            visible: true,
            cacheEpoch: 0,
            homeClock: Clock(() => now),
            snapshots: {
              for (final feature in FeatureId.values)
                feature: FeatureSnapshot(
                  feature: feature,
                  status: FeatureLoadStatus.empty,
                ),
            },
            onProjectTodos: (request) async => HomeTodoProjection([
              HomeTodo(
                id: 'signin:synthetic',
                feature: FeatureId.signin,
                title: '午夜前上课',
                subtitle: '合成课程',
                statusLabel: '未签到',
                timeLabel: '合成时段',
                sortTime: request.now,
                signin: const SigninPresentation(
                  courseId: 'synthetic-course',
                  actionTarget: 'old-target',
                  classBeginTime: '23:50',
                  classEndTime: '23:59:59',
                  signStatus: 0,
                ),
              ),
            ]),
            onFeatureTap: (_) {},
            onTodoTap: (_) {},
            onRefresh: () async {},
            onRetryFeature: (_) async {
              refreshes++;
            },
            onFetchSigninQr: (_, _) async {
              qrFetches++;
              return _qr;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    now = DateTime.parse('2026-03-25T00:00:05+08:00');
    await tester.tap(_button);
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(qrFetches, 0);
    expect(_sheet, findsNothing);
  });

  testWidgets('首页连点只打开一张面板，确认已签到后关闭并移除对应待办', (tester) async {
    await withClock(_inWindow, () async {
      final state = await mount(tester, check: (_) async => true);
      await tester.tap(_button.first);
      await tester.tap(_button.first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(state.qrTargets, ['canonical-1']);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(_sheet, findsNothing);
      expect(find.text('课程1'), findsNothing);
      expect(find.text('课程2'), findsOneWidget);
      expect(state.prepares, 0);
      expect(state.commits, 0);
    });
  });

  testWidgets('首页二维码获取失败保留待办，不自动重试或提交', (tester) async {
    await withClock(_inWindow, () async {
      final state = await mount(tester, fetchFailure: true);
      await tester.tap(_button.first);
      await tester.pumpAndSettle();
      expect(find.text('二维码获取失败'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(state.qrTargets, ['canonical-1']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('课程1'), findsOneWidget);
      expect(state.commits, 0);
    });
  });

  testWidgets('首页签到状态读取失败保留待办和二维码，不提交', (tester) async {
    await withClock(_inWindow, () async {
      final state = await mount(
        tester,
        check: (_) async => throw StateError('合成错误'),
      );
      await tester.tap(_button.first);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(_sheet, findsOneWidget);
      expect(state.statusTargets, ['canonical-1']);
      expect(state.commits, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('课程1'), findsOneWidget);
    });
  });

  testWidgets('缓存签到卡只刷新，在线确认后才能打开二维码', (tester) async {
    await withClock(_inWindow, () async {
      final state = await mount(tester, stale: true);
      expect(tester.widget<FilledButton>(_button.first).onPressed, isNull);
      await tester.tap(find.text('课程1'));
      await tester.pumpAndSettle();
      expect(state.refreshes, 1);
      expect(state.qrTargets, isEmpty);
      expect(find.widgetWithText(AppBar, '首页'), findsOneWidget);
      await tester.tap(_button.first);
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(state.qrTargets, ['canonical-1']);
      expect(state.commits, 0);
    });
  });
}

class Scenario {
  int prepares = 0, commits = 0, refreshes = 0;
  final qrTargets = <String>[], statusTargets = <String>[];
}

Future<Scenario> mount(
  WidgetTester tester, {
  bool stale = false,
  bool fetchFailure = false,
  bool signed = false,
  Future<bool> Function(String)? check,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 1100);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final state = Scenario();
  final snapshots = {
    for (final feature in FeatureId.values)
      feature: FeatureSnapshot(
        feature: feature,
        status: FeatureLoadStatus.empty,
      ),
    FeatureId.signin: FeatureSnapshot(
      feature: FeatureId.signin,
      status: stale ? FeatureLoadStatus.stale : FeatureLoadStatus.success,
      details: [
        for (var index = 1; index <= 2; index++)
          FeatureDetail(
            title: '课程$index',
            presentation: SigninPresentation(
              courseId: 'display-$index',
              actionTarget: 'canonical-$index',
              classBeginTime: '14:00',
              classEndTime: '17:00',
              signStatus: signed && index == 1 ? 1 : 0,
            ),
          ),
      ],
    ),
  };
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (_, rebuild) => coordinatedShell(
          user: const UserSummary(username: 'synthetic'),
          snapshots: snapshots,
          routePolicy: RoutePolicy.direct,
          onRefresh: () async {},
          onRetryFeature: (feature) async {
            state.refreshes++;
            rebuild(
              () => snapshots[feature] = snapshots[feature]!.copyWith(
                status: FeatureLoadStatus.success,
              ),
            );
          },
          onFeatureQuery: (_, _) async {},
          onFetchSigninQr: (target, _) async {
            state.qrTargets.add(target);
            if (fetchFailure) throw StateError('合成错误');
            return _qr;
          },
          onCheckSigninStatus: check == null
              ? null
              : (target) async {
                  state.statusTargets.add(target);
                  final signed = await check(target);
                  if (signed) {
                    rebuild(() {
                      final snapshot = snapshots[FeatureId.signin]!;
                      snapshots[FeatureId.signin] = snapshot.copyWith(
                        details: [
                          for (final detail in snapshot.details)
                            if ((detail.presentation as SigninPresentation)
                                    .actionTarget !=
                                target)
                              detail,
                        ],
                      );
                    });
                  }
                  return signed;
                },
          onWritePrepareAttempt: (_) => state.prepares++,
          onCommitWrite: (_) async {
            state.commits++;
            throw StateError('二维码流程不得提交写入');
          },
          onLogout: () async {},
          onLogoutAndClearAccount: () async {},
          onRoutePolicyChanged: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}
