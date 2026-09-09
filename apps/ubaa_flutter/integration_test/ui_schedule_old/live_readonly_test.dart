import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 生产课表真实只读；仅输出状态/条数，不截取个人课表或执行写入。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产今日学期周次周课表及本地详情只读', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-e3b-') ||
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
      if (finder.evaluate().isEmpty) {
        final scroll = find
            .byElementPredicate(
              (e) =>
                  e.widget is Scrollable &&
                  (e.widget as Scrollable).axisDirection ==
                      AxisDirection.down &&
                  e is StatefulElement &&
                  (e.state as ScrollableState).position.viewportDimension > 100,
            )
            .hitTestable()
            .last;
        await tester.scrollUntilVisible(
          finder,
          240,
          scrollable: scroll,
          maxScrolls: 80,
        );
      }
      if (finder.hitTestable().evaluate().isEmpty) {
        await tester.ensureVisible(finder);
      }
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> loaded({int? previous}) async {
      await waitFor(
        () =>
            snapshot().status != FeatureLoadStatus.idle &&
            snapshot().status != FeatureLoadStatus.loading &&
            (previous == null ||
                snapshot().readContext?.requestRevision != previous),
      );
      final s = snapshot();
      debugPrint(
        '课表只读 status=${s.status.name} route=${s.resolvedRoute?.name} count=${s.details.length} view=${s.readContext?.query?.view.name} error=${s.error?.code.name}',
      );
      expect(
        s.status == FeatureLoadStatus.success ||
            s.status == FeatureLoadStatus.empty,
        isTrue,
      );
      expect(s.resolvedRoute?.name, route);
      await tester.pump(const Duration(milliseconds: 250));
    }

    await tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.apps_outlined),
      ),
    );
    await tap(find.widgetWithText(Card, FeatureId.schedule.title));
    await loaded();
    await tap(find.byTooltip('搜索与筛选'));
    await tap(find.text('今日课程').last);
    await tap(find.text('学期列表').last);
    final todayRevision = snapshot().readContext?.requestRevision;
    await tap(find.widgetWithText(FilledButton, '应用筛选'));
    await loaded(previous: todayRevision);
    await tap(find.widgetWithText(TextButton, '完成'));
    final terms = snapshot().details
        .where(
          (d) => d.presentation is TermPresentation && d.readNavigation != null,
        )
        .toList();
    expect(terms.isNotEmpty, isTrue);
    final selected = terms
        .where((d) => (d.presentation! as TermPresentation).selected)
        .toList();
    final term = selected.length == 1 ? selected.single : terms.first;
    debugPrint(
      '课表只读 termSelection=${selected.length == 1 ? 'current' : 'explicit_first_returned'}',
    );
    final termRevision = snapshot().readContext?.requestRevision;
    await tap(
      find.descendant(
        of: find.widgetWithText(Card, term.title),
        matching: find.text('查看周次'),
      ),
    );
    await loaded(previous: termRevision);
    final weeks = snapshot().details
        .where(
          (d) => d.presentation is WeekPresentation && d.readNavigation != null,
        )
        .toList();
    expect(weeks.isNotEmpty, isTrue);
    final current = weeks
        .where((d) => (d.presentation! as WeekPresentation).current)
        .toList();
    final week = current.length == 1 ? current.single : weeks.first;
    debugPrint(
      '课表只读 weekSelection=${current.length == 1 ? 'current' : 'explicit_first_returned'}',
    );
    final weekRevision = snapshot().readContext?.requestRevision;
    await tap(
      find.descendant(
        of: find.widgetWithText(Card, week.title),
        matching: find.text('查看周课表'),
      ),
    );
    await loaded(previous: weekRevision);
    final before = snapshot().readContext?.requestRevision;
    if (find.byKey(const ValueKey('schedule-block-0')).evaluate().isNotEmpty) {
      await tap(find.byKey(const ValueKey('schedule-block-0')));
      if (find.text('同一时段的课程').evaluate().isNotEmpty) {
        await tap(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(ListTile),
              )
              .first,
        );
      }
      expect(find.byType(AlertDialog).evaluate().isNotEmpty, isTrue);
      expect(find.text('课程代码').evaluate().isNotEmpty, isTrue);
      expect(snapshot().readContext?.requestRevision == before, isTrue);
      await tap(find.widgetWithText(TextButton, '关闭').last);
      if (find.text('同一时段的课程').evaluate().isNotEmpty) {
        await tap(find.widgetWithText(TextButton, '关闭').last);
      }
      debugPrint('课表只读 localDetail=true extraReads=0');
    } else {
      debugPrint('课表只读 localDetail=NOT_APPLICABLE reason=no_positioned_course');
    }
    await tap(find.byTooltip('搜索与筛选'));
    final chosen = week.presentation! as WeekPresentation;
    expect(
      tester
              .widget<TextField>(find.widgetWithText(TextField, '学期编码'))
              .controller!
              .text ==
          chosen.requestTerm,
      isTrue,
    );
    expect(
      tester
              .widget<TextField>(find.widgetWithText(TextField, '周次'))
              .controller!
              .text ==
          '${chosen.number}',
      isTrue,
    );
    await tap(find.widgetWithText(TextButton, '完成'));
    expect(snapshot().readContext?.requestRevision == before, isTrue);
    expect(
      find
          .byTooltip('实际路线：${route == 'direct' ? '直连' : 'WebVPN'}')
          .evaluate()
          .isNotEmpty,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    debugPrint('课表只读 完成 retainedDraft=true businessWrites=0');
  });
}
