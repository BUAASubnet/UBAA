import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'backend.dart';
part 'support.dart';

const _bannerKey = ValueKey('home-grade-update');
void main() {
  if (const bool.fromEnvironment('UBAA_UI_INSPECTION')) {
    WidgetsFlutterBinding.ensureInitialized();
    final backend = GradeWatchBackend();
    final store = MemoryGradeScoreStore();
    unawaited(() async {
      await store.write(
        backend.account,
        ConnectionMode.direct,
        const GradeScoreBaseline(
          termCode: '2026-2027-1',
          termName: '合成当前学期',
          scores: [
            GradeScoreEntry(
              key: 'code:GRADE-SAFE',
              courseName: '合成数学课程',
              courseCode: 'GRADE-SAFE',
              score: '70',
            ),
          ],
        ),
      );
      runApp(
        UbaaFlutterApp(
          backend: backend,
          credentialVault: MemoryCredentialVault(),
          gradeScoreStore: store,
        ),
      );
    }());
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final brightness in Brightness.values) {
    testWidgets('原生成绩基线损坏清理反馈 ${brightness.name}', (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'ubaa-grade-watch-clear-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/scores.json');
      await mount(
        tester,
        GradeWatchBackend(),
        brightness,
        store: FileGradeScoreStore(file),
      );
      await file.writeAsString('合成损坏文件');
      await tap(tester, find.byTooltip('打开导航菜单'));
      await tap(tester, find.text('设置'));
      await tap(tester, find.text('退出并清除本机账号'));
      await tap(tester, find.widgetWithText(FilledButton, '退出并清除'));
      expect(find.byType(UbaaLoginView), findsOneWidget);
      expect(find.text('本机数据未能完全清除，请稍后重试。'), findsOneWidget);
      expect(await file.readAsString(), '合成损坏文件');
      await capture(
        binding,
        tester,
        '${brightness.name}-grade-watch-clear-error',
        '损坏的本地合成成绩文件不被覆盖；退出完成后明确说明未完全清除',
      );
    });
    testWidgets('首页成绩变化旧横幅与查看忽略 ${brightness.name}', (tester) async {
      final backend = GradeWatchBackend();
      await mount(tester, backend, brightness);
      Future<void> shot(String name, String steps) => capture(
        binding,
        tester,
        '${brightness.name}-grade-watch-$name',
        steps,
      );
      expect(find.byKey(_bannerKey), findsNothing);
      await shot('first', '首次已读取只建立基线，不制造更新提醒');
      backend.score = '90';
      await refresh(tester);
      expect(find.text('合成数学课程 成绩已更新'), findsOneWidget);
      expect(
        tester.getBottomRight(find.byKey(_bannerKey)).dy,
        lessThan(tester.getTopLeft(find.text('合成今日课程')).dy),
      );
      await shot('notice', '横幅位于今日标题之后、课程之前；单门消息保留旧文案');
      await refresh(tester);
      expect(find.byKey(_bannerKey), findsOneWidget);
      await tap(tester, find.widgetWithText(TextButton, '忽略'));
      await refresh(tester);
      expect(find.byKey(_bannerKey), findsNothing);
      await shot('ignored', '忽略后同分刷新不重复提醒');
      backend.score = '100';
      await refresh(tester);
      await tap(tester, find.widgetWithText(TextButton, '查看'));
      expect(
        shell(tester).snapshots[FeatureId.grades]!.readContext!.query!.term,
        '2026-2027-1',
      );
      await shot('open-grades', '查看消费通知并打开该学期成绩，功能页手机无全局底栏');
      await tap(tester, find.byTooltip('返回'));
      expect(find.byKey(_bannerKey), findsNothing);
      await shot('return', '返回首页已消费通知不再出现');
      expect(backend.commitCalls, 0);
    });
    for (final variant in ['multiple', 'long']) {
      testWidgets('首页成绩变化 $variant ${brightness.name}', (tester) async {
        final backend = GradeWatchBackend(
          state: variant,
          multiple: variant == 'multiple',
        );
        if (variant == 'long') {
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        }
        await mount(tester, backend, brightness);
        backend.score = '90';
        await refresh(tester);
        expect(find.byKey(_bannerKey), findsOneWidget);
        if (variant == 'multiple') {
          expect(find.text('合成当前学期 有 3 门成绩更新'), findsOneWidget);
        }
        await capture(
          binding,
          tester,
          '${brightness.name}-grade-watch-$variant',
          '多门摘要或1.3长名称保持完整信息，查看忽略可操作',
        );
        await tap(tester, find.widgetWithText(TextButton, '忽略'));
        expect(find.byKey(_bannerKey), findsNothing);
      });
    }
    testWidgets('首页成绩空集合与失败保留基线 ${brightness.name}', (tester) async {
      final backend = GradeWatchBackend();
      await mount(tester, backend, brightness);
      backend.emptyCurrent = true;
      await refresh(tester);
      expect(find.byKey(_bannerKey), findsNothing);
      await capture(
        binding,
        tester,
        '${brightness.name}-grade-watch-empty',
        '空集合不覆盖已有基线',
      );
      backend.emptyCurrent = false;
      backend.failGrades = true;
      backend.score = '90';
      await refresh(tester);
      expect(find.byKey(_bannerKey), findsNothing);
      await capture(
        binding,
        tester,
        '${brightness.name}-grade-watch-failure',
        '成绩读取失败不伪造更新，也不阻挡课程待办',
      );
      backend.failGrades = false;
      await refresh(tester);
      expect(find.byKey(_bannerKey), findsOneWidget);
      await capture(
        binding,
        tester,
        '${brightness.name}-grade-watch-recovered',
        '恢复后和原有效基线比较，显示确实发生的变化',
      );
    });
    testWidgets('原生成绩文件基线重建与账号路线隔离 ${brightness.name}', (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'ubaa-grade-watch-native-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/scores.json');
      final first = GradeWatchBackend();
      await mount(tester, first, brightness, store: FileGradeScoreStore(file));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final second = GradeWatchBackend()..score = '90';
      final store = FileGradeScoreStore(file);
      await mount(tester, second, brightness, store: store);
      expect(find.byKey(_bannerKey), findsOneWidget);
      await capture(
        binding,
        tester,
        '${brightness.name}-grade-watch-restored',
        '重建宿主与文件存储实例后沿磁盘基线识别变化',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final another = GradeWatchBackend()
        ..account = 'another-grade-fixture'
        ..score = '99';
      await mount(tester, another, brightness, store: store);
      expect(find.byKey(_bannerKey), findsNothing);
      await capture(
        binding,
        tester,
        '${brightness.name}-grade-watch-other-account',
        '另一个合成账号首次建立独立基线，不比较前账号',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final routed = GradeWatchBackend()
        ..gradeRoute = ConnectionMode.webvpn
        ..score = '100';
      await mount(tester, routed, brightness, store: store);
      expect(find.byKey(_bannerKey), findsNothing);
      await tap(tester, find.byTooltip('实际路线：混合'));
      expect(find.text('成绩检查：WebVPN'), findsOneWidget);
      await capture(
        binding,
        tester,
        '${brightness.name}-grade-watch-first-route',
        '首次基线没有通知时仍展示成绩检查实际WebVPN路线',
      );
      await tap(tester, find.widgetWithText(TextButton, '关闭'));
      routed.score = '110';
      await refresh(tester);
      expect(find.byKey(_bannerKey), findsOneWidget);
      await tap(tester, find.byTooltip('实际路线：混合'));
      expect(find.text('成绩更新：WebVPN'), findsOneWidget);
      await capture(
        binding,
        tester,
        '${brightness.name}-grade-watch-route',
        '实际路线分别保存，提醒来源进入唯一顶栏说明',
      );
      await tap(tester, find.widgetWithText(TextButton, '关闭'));
      await shell(tester).onLogoutAndClearAccount();
      await tester.pumpAndSettle();
      expect(await store.read(routed.account, ConnectionMode.direct), isNull);
      expect(await store.read(routed.account, ConnectionMode.webvpn), isNull);
      expect(
        await store.read(another.account, ConnectionMode.direct),
        isNotNull,
      );
      expect(routed.commitCalls, 0);
    });
  }
}

UbaaMainShell shell(WidgetTester tester) =>
    tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
Future<void> mount(
  WidgetTester tester,
  GradeWatchBackend backend,
  Brightness brightness, {
  GradeScoreStore? store,
}) async {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    UbaaFlutterApp(
      backend: backend,
      credentialVault: MemoryCredentialVault(),
      gradeScoreStore: store,
    ),
  );
  await tester.pumpAndSettle();
  await shell(tester).onCheckGradeUpdates!();
  await tester.pumpAndSettle();
}

Future<void> refresh(WidgetTester tester) async {
  await tap(tester, find.byTooltip('刷新'));
  await shell(tester).onCheckGradeUpdates!();
  await tester.pumpAndSettle();
}
