import '../../navigation.dart';
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
  testWidgets('生产相邻周与跨学期周次选择只读', (tester) async {
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

    final dates = find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d{1,2}-\d{1,2}$').hasMatch(w.data ?? ''),
    );
    await tap(uiDestinationFinder(tester, UiDestination.academic));
    await tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await loaded(FeatureQueryView.scheduleWeek);
    debugPrint('周导航只读 automatic=true headerDates=${dates.evaluate().length}');
    expect(dates.evaluate().isEmpty || dates.evaluate().length == 7, isTrue);
    final current = snapshot().readContext!.query!;
    final before = snapshot().readContext!.requestRevision;
    // 周次沿课表自身的上一周/下一周与教学周选择器切换，不经手填。
    bool enabled(String tooltip) => find
        .byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == tooltip && w.onPressed != null,
        )
        .evaluate()
        .isNotEmpty;
    final step = enabled('下一周') ? '下一周' : '上一周';
    await tap(find.byTooltip(step));
    await loaded(FeatureQueryView.scheduleWeek, previous: before);
    final next = snapshot().readContext!.query!.week;
    expect(next != null && next > 0 && next != current.week, isTrue);
    expect(snapshot().readContext?.query?.term == current.term, isTrue);
    debugPrint(
      '周导航只读 adjacent=true step=$step headerDates=${dates.evaluate().length}',
    );

    await tap(find.byTooltip('选择学期'));
    final termChoices = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate(
        (w) => w is ListTile && w.onTap != null && !w.selected,
      ),
    );
    await waitFor(() => termChoices.evaluate().isNotEmpty);
    final termRevision = snapshot().readContext!.requestRevision;
    await tap(termChoices.first);
    // 新学期有唯一本周时自动定位；否则停在教学周提示，由用户选择。
    await waitFor(
      () =>
          (snapshot().readContext?.query?.view ==
                  FeatureQueryView.scheduleWeek &&
              snapshot().readContext!.requestRevision != termRevision &&
              snapshot().status != FeatureLoadStatus.loading) ||
          find.widgetWithText(FilledButton, '选择教学周').evaluate().isNotEmpty,
    );
    if (find.widgetWithText(FilledButton, '选择教学周').evaluate().isNotEmpty) {
      await tap(find.widgetWithText(FilledButton, '选择教学周'));
      final weekChoices = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate(
          (w) => w is ListTile && w.onTap != null,
        ),
      );
      await waitFor(() => weekChoices.evaluate().isNotEmpty);
      final weekRevision = snapshot().readContext!.requestRevision;
      await tap(weekChoices.first);
      await loaded(FeatureQueryView.scheduleWeek, previous: weekRevision);
    } else {
      await loaded(FeatureQueryView.scheduleWeek);
    }
    final term = snapshot().readContext?.query?.term;
    expect(term != null && term != current.term, isTrue);
    expect((snapshot().readContext?.query?.week ?? 0) > 0, isTrue);
    debugPrint('周导航只读 termChanged=true headerDates=${dates.evaluate().length}');
    // 今日课程视图已不在课表页提供，首页今日课表另有覆盖。
    expect(
      find
          .byTooltip('实际路线：${route == 'direct' ? '直连' : 'WebVPN'}')
          .evaluate()
          .isNotEmpty,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    debugPrint('周导航只读 完成 businessWrites=0');
  });
}
