import '../../navigation.dart';
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
  testWidgets('生产课表自动定位与学期周次选择及本地详情只读', (tester) async {
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

    await tap(uiDestinationFinder(tester, UiDestination.academic));
    await tap(find.widgetWithText(Card, FeatureId.schedule.title));
    // 进入课表即自动定位：学期列表 → 教学周 → 本周课表；三层由页面依次读取。
    await waitFor(
      () =>
          (snapshot().readContext?.query?.view ==
                  FeatureQueryView.scheduleWeek &&
              snapshot().status != FeatureLoadStatus.loading) ||
          find.text('请选择学期').evaluate().isNotEmpty ||
          find.text('请选择教学周').evaluate().isNotEmpty,
    );
    if (find.text('请选择学期').evaluate().isNotEmpty ||
        find.text('请选择教学周').evaluate().isNotEmpty) {
      // 当前学期或本周不唯一时停在选择提示，沿课表自身选择器显式选第一项。
      final needTerm = find.text('请选择学期').evaluate().isNotEmpty;
      await tap(find.widgetWithText(FilledButton, needTerm ? '选择学期' : '选择教学周'));
      final choices = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate(
          (w) => w is ListTile && w.onTap != null,
        ),
      );
      await waitFor(() => choices.evaluate().isNotEmpty);
      await tap(choices.first);
      if (needTerm) {
        await waitFor(
          () =>
              snapshot().readContext?.query?.view ==
                  FeatureQueryView.scheduleWeek ||
              find.widgetWithText(FilledButton, '选择教学周').evaluate().isNotEmpty,
        );
        if (find.widgetWithText(FilledButton, '选择教学周').evaluate().isNotEmpty) {
          await tap(find.widgetWithText(FilledButton, '选择教学周'));
          await waitFor(() => choices.evaluate().isNotEmpty);
          await tap(choices.first);
        }
      }
      debugPrint('课表只读 selection=explicit_first_returned');
    } else {
      debugPrint('课表只读 selection=automatic_current');
    }
    await loaded();
    final chosen = snapshot().readContext!.query!;
    expect(chosen.view, FeatureQueryView.scheduleWeek);
    expect(chosen.term != null && (chosen.week ?? 0) > 0, isTrue);
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
    // 本地详情不改变已定位的学期与周次。
    expect(snapshot().readContext?.query?.term == chosen.term, isTrue);
    expect(snapshot().readContext?.query?.week == chosen.week, isTrue);
    expect(snapshot().readContext?.requestRevision == before, isTrue);
    expect(
      find
          .byTooltip('实际路线：${route == 'direct' ? '直连' : 'WebVPN'}')
          .evaluate()
          .isNotEmpty,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    debugPrint('课表只读 完成 retainedWeek=true businessWrites=0');
  });
}
