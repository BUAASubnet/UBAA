import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 生产启动的博雅五类读取；只输出状态枚举与数量，不截图或准备业务写入。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产博雅旧版列表详情已选统计与资料只读复验', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-') ||
        (route != 'direct' && route != 'webvpn')) {
      throw StateError('必须显式提供生产只读开关、隔离配置和预期路线');
    }
    Widget? app;
    await bootstrapUbaaFlutterApp(runApplication: (value) => app = value);
    await tester.pumpWidget(app!);
    Future<void> waitFor(bool Function() ready, String reason) async {
      for (var step = 0; step < 480 && !ready(); step++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(ready(), isTrue, reason: reason);
    }

    await waitFor(
      () =>
          find.byType(UbaaMainShell).evaluate().isNotEmpty ||
          find.byType(UbaaLoginView).evaluate().isNotEmpty,
      '隔离生产会话未能恢复',
    );
    final login = find.byType(UbaaLoginView);
    if (login.evaluate().isNotEmpty) {
      debugPrint(
        '博雅只读启动 login=true '
        'error=${tester.widget<UbaaLoginView>(login).error?.code.name}',
      );
    }
    expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
    FeatureSnapshot snapshot() => tester
        .widget<UbaaMainShell>(find.byType(UbaaMainShell))
        .snapshots[FeatureId.bykc]!;
    Future<void> tap(Finder finder) async {
      expect(finder.evaluate().isNotEmpty, isTrue, reason: '只读入口未出现');
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 150));
    }

    Future<void> loaded(FeatureQueryView view) async {
      await waitFor(() {
        final value = snapshot();
        // 默认loadFeature结果被旧版根入口复用时query为null；显式查询仍精确匹配。
        final matches =
            value.readContext != null &&
            (value.readContext?.query?.view == view ||
                (view == FeatureQueryView.summary &&
                    value.readContext?.query == null));
        return matches &&
            value.status != FeatureLoadStatus.idle &&
            value.status != FeatureLoadStatus.loading;
      }, '博雅只读查询未在限定时间完成');
      final value = snapshot();
      debugPrint(
        '博雅只读 view=${view.name} status=${value.status.name} '
        'route=${value.resolvedRoute?.name} count=${value.details.length} '
        'displayPage=${value.pagination?.page} error=${value.error?.code.name}',
      );
      expect(
        value.status == FeatureLoadStatus.success ||
            value.status == FeatureLoadStatus.empty,
        isTrue,
      );
      expect(value.resolvedRoute?.name, route);
      await tester.pump(const Duration(milliseconds: 250));
    }

    await tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.apps_outlined),
      ),
    );
    await tap(find.widgetWithText(Card, FeatureId.bykc.title));
    await tap(find.widgetWithText(Card, '选择课程'));
    await loaded(FeatureQueryView.summary);
    expect(snapshot().details.isNotEmpty, isTrue);
    expect(
      snapshot().details.every((d) => d.presentation is BykcCoursePresentation),
      isTrue,
    );
    expect(find.byType(TextField).evaluate().isEmpty, isTrue);
    await tap(find.byTooltip('搜索与筛选'));
    await tap(find.text('状态不限'));
    await tap(find.widgetWithText(TextButton, '完成'));
    final course =
        snapshot().details.first.presentation as BykcCoursePresentation;
    await tap(find.widgetWithText(Card, course.courseName).first);
    await loaded(FeatureQueryView.bykcDetail);
    expect(
      snapshot().details.single.presentation is BykcCoursePresentation,
      isTrue,
    );
    expect(
      (snapshot().details.single.presentation as BykcCoursePresentation).id ==
          course.id,
      isTrue,
    );
    expect(find.widgetWithText(AppBar, '课程详情').evaluate().isNotEmpty, isTrue);
    await tap(find.byTooltip('返回'));
    await tap(find.byTooltip('返回'));
    await tap(find.widgetWithText(Card, '我的课程'));
    await loaded(FeatureQueryView.bykcChosenCourses);
    expect(
      snapshot().details.every((d) => d.presentation is BykcChosenPresentation),
      isTrue,
    );
    if (snapshot().details.isNotEmpty) {
      final chosen =
          snapshot().details.first.presentation as BykcChosenPresentation;
      final revision = snapshot().readContext?.requestRevision;
      await tap(find.widgetWithText(Card, chosen.courseName).first);
      expect(find.widgetWithText(AppBar, '课程详情').evaluate().isNotEmpty, isTrue);
      expect(snapshot().readContext?.requestRevision == revision, isTrue);
      debugPrint('博雅只读 chosenLocalDetail=true extraRead=false');
      await tap(find.byTooltip('返回'));
    } else {
      debugPrint('博雅只读 chosenLocalDetail=未执行 reason=当前学期无已选记录');
    }
    await tap(find.byTooltip('返回'));
    await tap(find.widgetWithText(Card, '课程统计'));
    await loaded(FeatureQueryView.bykcStatistics);
    expect(
      snapshot().details.any(
        (d) => d.presentation is BykcStatisticsPresentation,
      ),
      isTrue,
    );
    expect(find.text('总体净有效次数').evaluate().isNotEmpty, isTrue);
    await tap(find.byTooltip('搜索与筛选'));
    await tap(find.byType(DropdownButton<FeatureQueryView>));
    await tap(find.text('个人资料').last);
    await tap(find.text('应用筛选'));
    await loaded(FeatureQueryView.bykcProfile);
    await tap(find.widgetWithText(TextButton, '完成'));
    expect(
      snapshot().details.any((d) => d.presentation is BykcProfilePresentation),
      isTrue,
    );
    expect(find.byType(TextField).evaluate().isEmpty, isTrue);
    debugPrint('生产博雅五类只读操作完成，businessWrites=0');
  });
}
