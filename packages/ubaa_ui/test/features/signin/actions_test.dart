import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/coursework/signin_qr_sheet.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../support/navigation.dart';
import '../../support/write_harness.dart';

final _clock = Clock.fixed(DateTime.utc(2026, 11, 26, 7));
final _sheet = find.byType(SigninQrSheet);

void main() {
  testWidgets('已签到课程的二维码持续刷新，不查询状态或自动关闭', (tester) async {
    await withClock(_clock, () async {
      final offsets = <Duration>[];
      var checks = 0;
      await _mount(
        tester,
        signed: true,
        fetch: (target, offset) async {
          expect(target, 'synthetic-target');
          offsets.add(offset);
          return '合成二维码';
        },
        check: (_) async {
          checks++;
          return true;
        },
        save: (_, _) async => true,
      );
      expect(find.text('已签到'), findsOneWidget);
      expect(find.text('上课'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, '二维码'));
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(offsets, [Duration.zero]);
      await tester.pump(const Duration(seconds: 2));
      expect(offsets, [Duration.zero, Duration.zero]);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(_sheet, findsOneWidget);
      expect(checks, 0);
      await tester.tap(find.textContaining(RegExp(r'^保存(?:图片|到相册)$')));
      await tester.pump();
      expect(offsets.last, const Duration(seconds: 2));
    });
  });

  for (final instant in [
    DateTime.utc(2026, 11, 26, 6, 49),
    DateTime.utc(2026, 11, 26, 9, 1),
  ]) {
    testWidgets('已签到课程在窗口外没有二维码入口（$instant）', (tester) async {
      await withClock(Clock.fixed(instant), () async {
        await _mount(tester, signed: true, fetch: (_, _) async => '合成二维码');
        expect(find.text('已签到'), findsOneWidget);
        expect(find.text('二维码'), findsNothing);
        expect(find.text('上课'), findsNothing);
      });
    });
  }

  testWidgets('每日课程二维码获取失败只显示固定提示，可手动重取', (tester) async {
    await withClock(_clock, () async {
      var fetches = 0;
      await _open(
        tester,
        fetch: (_, _) async {
          if (++fetches == 1) throw StateError('合成内部错误');
          return '合成二维码';
        },
      );
      expect(find.text('二维码获取失败'), findsOneWidget);
      expect(find.textContaining('合成内部错误'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(fetches, 1);
      await tester.tap(find.text('重新获取'));
      await tester.pumpAndSettle();
      expect(fetches, 2);
      expect(find.text('二维码获取失败'), findsNothing);
    });
  });

  testWidgets('每日课程签到状态读取失败时面板保留，直到读到已签到', (tester) async {
    await withClock(_clock, () async {
      var checks = 0;
      await _open(
        tester,
        fetch: (_, _) async => '合成二维码',
        check: (_) async {
          if (++checks == 1) throw StateError('合成内部错误');
          return true;
        },
      );
      await tester.pump(const Duration(seconds: 3));
      expect(_sheet, findsOneWidget);
      expect(find.textContaining('合成内部错误'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(checks, 2);
      expect(_sheet, findsNothing);
    });
  });

  testWidgets('每日课程点击上课直接打开二维码且不调用写入', (tester) async {
    await withClock(_clock, () async {
      final targets = <String>[];
      await _open(
        tester,
        fetch: (target, _) async {
          targets.add(target);
          return '合成二维码';
        },
      );
      expect(_sheet, findsOneWidget);
      expect(targets, ['synthetic-target']);
      expect(find.text('确认每日课程'), findsNothing);
    });
  });
}

Future<void> _open(
  WidgetTester tester, {
  required SigninCourseQrFetcher fetch,
  SigninStatusChecker? check,
}) async {
  await _mount(tester, fetch: fetch, check: check);
  await tester.tap(find.widgetWithText(FilledButton, '上课'));
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester, {
  required SigninCourseQrFetcher fetch,
  SigninStatusChecker? check,
  SigninQrImageSaver? save,
  bool signed = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: UbaaTheme.light(),
      home: coordinatedShell(
        user: const UserSummary(username: 'synthetic'),
        snapshots: {
          FeatureId.signin: FeatureSnapshot(
            feature: FeatureId.signin,
            status: FeatureLoadStatus.success,
            details: [
              FeatureDetail(
                title: '合成课程',
                presentation: SigninPresentation(
                  courseId: 'synthetic-course',
                  actionTarget: 'synthetic-target',
                  classBeginTime: '15:00',
                  classEndTime: '17:00',
                  signStatus: signed ? 1 : 0,
                ),
                actions: const [
                  SigninPerformAction(
                    scheduleId: 'legacy-target',
                    eligibility: ActionEligibility.allowed,
                  ),
                ],
              ),
            ],
          ),
        },
        routePolicy: RoutePolicy.auto,
        onRefresh: () async {},
        onRetryFeature: (_) async {},
        onFetchSigninQr: fetch,
        onSaveSigninQr: save,
        onCheckSigninStatus: check,
        onWritePrepareAttempt: (_) => fail('二维码入口不得准备写入'),
        onCommitWrite: (_) async => fail('二维码入口不得提交写入'),
        onLogout: () async {},
        onLogoutAndClearAccount: () async {},
        onRoutePolicyChanged: (_) {},
      ),
    ),
  );
  await tester.tap(find.byIcon(UiDestination.study.icon));
  await tester.pumpAndSettle();
  await openFeature(tester, FeatureId.signin);
}
