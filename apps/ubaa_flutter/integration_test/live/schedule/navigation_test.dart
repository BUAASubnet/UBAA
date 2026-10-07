import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 生产周导航仅只读，证据只输出状态/数量，不截图个人课程或输出参数原值。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产自然周选择与跨学期今日兼容只读', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-e3c-') ||
        !{'direct', 'webvpn'}.contains(route)) {
      throw StateError('必须显式提供本批生产只读配置与预期路线');
    }
    Widget? app;
    await bootstrapUbaaFlutterApp(runApplication: (value) => app = value);
    await tester.pumpWidget(app!);
    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 480 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(ready(), isTrue, reason: '只读未在限定时间内完成');
    }

    await waitFor(
      () =>
          find.byType(UbaaMainShell).evaluate().isNotEmpty ||
          find.byType(UbaaLoginView).evaluate().isNotEmpty,
    );
    expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
    FeatureSnapshot snapshot() => tester
        .widget<UbaaMainShell>(find.byType(UbaaMainShell))
        .snapshots[FeatureId.schedule]!;
    Future<void> tap(Finder finder) async {
      if (finder.hitTestable().evaluate().isEmpty) {
        await tester.ensureVisible(finder);
      }
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> loaded(FeatureQueryView view, {int? previous}) async {
      await waitFor(
        () =>
            snapshot().readContext?.query?.view == view &&
            snapshot().status != FeatureLoadStatus.loading &&
            snapshot().status != FeatureLoadStatus.idle &&
            (previous == null ||
                snapshot().readContext?.requestRevision != previous),
      );
      final s = snapshot();
      debugPrint(
        '周导航只读 status=${s.status.name} route=${s.resolvedRoute?.name} count=${s.details.length} view=$view error=${s.error?.code.name}',
      );
      expect(
        s.status == FeatureLoadStatus.success ||
            s.status == FeatureLoadStatus.empty,
        isTrue,
      );
      expect(s.resolvedRoute?.name, route);
      await tester.pump(const Duration(milliseconds: 250));
    }

    String draft(String label) => tester
        .widget<TextField>(find.widgetWithText(TextField, label))
        .controller!
        .text;
    final dates = find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d{1,2}-\d{1,2}$').hasMatch(w.data ?? ''),
    );
    await tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.apps_outlined),
      ),
    );
    await tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await loaded(FeatureQueryView.scheduleWeek);
    debugPrint('周导航只读 automatic=true headerDates=${dates.evaluate().length}');
    expect(dates.evaluate().isEmpty || dates.evaluate().length == 7, isTrue);
    final current = snapshot().readContext!.query!;
    final before = snapshot().readContext!.requestRevision;
    await tap(find.byTooltip('搜索与筛选'));
    expect(draft('学期编码') == current.term, isTrue);
    expect(draft('周次') == '${current.week}', isTrue);
    await tap(find.byTooltip('下一教学周'));
    await waitFor(
      () => find
          .byWidgetPredicate(
            (w) =>
                w is IconButton && w.tooltip == '下一教学周' && w.onPressed != null,
          )
          .evaluate()
          .isNotEmpty,
    );
    if (draft('周次') == '${current.week}') {
      await tap(find.byTooltip('上一教学周'));
      await waitFor(
        () => find
            .byWidgetPredicate(
              (w) =>
                  w is IconButton &&
                  w.tooltip == '上一教学周' &&
                  w.onPressed != null,
            )
            .evaluate()
            .isNotEmpty,
      );
    }
    final next = int.tryParse(draft('周次'));
    expect(next != null && next > 0, isTrue);
    expect(snapshot().readContext?.requestRevision == before, isTrue);
    await tap(find.widgetWithText(TextButton, '完成'));
    await tap(find.byTooltip('搜索与筛选'));
    expect(draft('周次') == '$next', isTrue);
    await tap(find.text('应用筛选'));
    await loaded(FeatureQueryView.scheduleWeek, previous: before);
    await tap(find.widgetWithText(TextButton, '完成'));
    expect(snapshot().readContext?.query?.week == next, isTrue);
    debugPrint(
      '周导航只读 adjacent=${next != current.week} retainedDraft=true headerDates=${dates.evaluate().length}',
    );

    await tap(find.byTooltip('搜索与筛选'));
    await tap(find.widgetWithText(OutlinedButton, '选择学期'));
    final termChoices = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (w) => w is ListTile && w.onTap != null && !w.selected,
      ),
    );
    await waitFor(() => termChoices.evaluate().isNotEmpty);
    await tap(termChoices.first);
    expect(draft('学期编码') != current.term, isTrue);
    expect(draft('周次').isEmpty, isTrue);
    final term = draft('学期编码');
    await tap(find.widgetWithText(OutlinedButton, '选择教学周'));
    final weekChoices = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate((w) => w is ListTile && w.onTap != null),
    );
    await waitFor(() => weekChoices.evaluate().isNotEmpty);
    await tap(weekChoices.first);
    final week = int.tryParse(draft('周次'));
    expect(week != null && week > 0, isTrue);
    final previous = snapshot().readContext!.requestRevision;
    await tap(find.text('应用筛选'));
    await loaded(FeatureQueryView.scheduleWeek, previous: previous);
    await tap(find.widgetWithText(TextButton, '完成'));
    expect(snapshot().readContext?.query?.term == term, isTrue);
    expect(snapshot().readContext?.query?.week == week, isTrue);
    debugPrint('周导航只读 termChanged=true headerDates=${dates.evaluate().length}');

    await tap(find.byTooltip('搜索与筛选'));
    await tap(find.byType(DropdownButton<FeatureQueryView>));
    await tap(find.text('今日课程').last);
    final termRevision = snapshot().readContext!.requestRevision;
    await tap(find.text('应用筛选'));
    await loaded(FeatureQueryView.scheduleToday, previous: termRevision);
    await tap(find.widgetWithText(TextButton, '完成'));
    expect(snapshot().readContext?.query?.term == null, isTrue);
    expect(snapshot().readContext?.query?.week == null, isTrue);
    expect(
      find
          .byTooltip('实际路线：${route == 'direct' ? '直连' : 'WebVPN'}')
          .evaluate()
          .isNotEmpty,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    debugPrint('周导航只读 完成 todayCompatibility=true businessWrites=0');
  });
}
