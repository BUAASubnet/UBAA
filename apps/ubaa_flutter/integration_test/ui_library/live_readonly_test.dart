import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 生产图书馆顺序只读；不选座、不准备、不提交、不截取个人数据。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产图书馆楼馆分区时段座位与记录只读', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-lib-final-') ||
        !{'direct', 'webvpn'}.contains(route)) {
      throw StateError('必须提供本批独立只读配置和路线');
    }
    Widget? app;
    await bootstrapUbaaFlutterApp(runApplication: (value) => app = value);
    await tester.pumpWidget(app!);
    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 480 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(ready(), isTrue, reason: '只读未在限定时间完成');
    }

    await waitFor(
      () =>
          find.byType(UbaaMainShell).evaluate().isNotEmpty ||
          find.byType(UbaaLoginView).evaluate().isNotEmpty,
    );
    expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
    FeatureSnapshot snapshot() => tester
        .widget<UbaaMainShell>(find.byType(UbaaMainShell))
        .snapshots[FeatureId.libbook]!;
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
        await tester.scrollUntilVisible(finder, 250, scrollable: scroll);
      }
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 150));
    }

    Future<void> loaded(FeatureQueryView view) async {
      String? last;
      var changedAt = DateTime.now();
      await waitFor(() {
        final value = snapshot();
        final query = value.readContext?.query;
        final state =
            'view=${query?.view.name} status=${value.status.name} route=${value.resolvedRoute?.name} count=${value.details.length} error=${value.error?.code.name}';
        if (state != last) {
          last = state;
          changedAt = DateTime.now();
          debugPrint('图书馆只读进度 $state');
          final libraries = value.details
              .map((d) => d.presentation)
              .whereType<LibbookLibraryPresentation>();
          final areas = value.details
              .map((d) => d.presentation)
              .whereType<LibbookAreaPresentation>();
          debugPrint(
            '图书馆只读结构 libraries=${libraries.length} storeys=${libraries.fold<int>(0, (n, p) => n + p.storeys.length)} areas=${areas.length} matchedAreas=${areas.where((p) => p.premisesId == query?.premisesId && (query?.storeyId == null || p.storeyId == query?.storeyId)).length} emptyPremises=${areas.where((p) => p.premisesId.trim().isEmpty).length} emptyStorey=${areas.where((p) => p.storeyId.trim().isEmpty).length}',
          );
        }
        if (view == FeatureQueryView.libbookAreaDetail &&
            query?.view == FeatureQueryView.libbookAreas &&
            value.status == FeatureLoadStatus.success &&
            DateTime.now().difference(changedAt).inSeconds >= 5) {
          throw StateError('分区列表已完成但未进入详情，结构计数见安全记录');
        }
        return query?.view == view &&
            value.status != FeatureLoadStatus.loading &&
            value.status != FeatureLoadStatus.idle;
      });
      final value = snapshot();
      debugPrint(
        '图书馆只读 view=${view.name} status=${value.status.name} route=${value.resolvedRoute?.name} count=${value.details.length} error=${value.error?.code.name}',
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
    await tap(find.widgetWithText(Card, FeatureId.libbook.title));
    await tap(find.widgetWithText(Card, '预约座位'));
    await loaded(FeatureQueryView.libbookAreaDetail);
    final area =
        snapshot().details.single.presentation!
            as LibbookAreaDetailPresentation;
    final queryDay = snapshot().readContext!.query!.date;
    expect(queryDay != null, isTrue);
    expect(find.byType(TextField), findsNothing);
    debugPrint(
      '图书馆只读 areaDetail=true slots=${area.timeSlots.length} dates=${area.availableDates.length}',
    );
    if (area.timeSlots.isNotEmpty) {
      final slot = area.timeSlots.first;
      await tap(
        find.widgetWithText(
          ActionChip,
          '${slot.label} ${slot.start}–${slot.end}',
        ),
      );
      final dateField = find.widgetWithText(TextField, '日期');
      await tap(dateField);
      final date =
          '${queryDay!.year}-${queryDay.month.toString().padLeft(2, '0')}-${queryDay.day.toString().padLeft(2, '0')}';
      // 明确查询原日期与所选时段，不声称两个独立公开列表有关联或可预约。
      await tester.enterText(dateField, date);
      await tap(find.text('应用筛选'));
      await loaded(FeatureQueryView.libbookSeats);
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(find.widgetWithText(TextButton, '完成'));
      expect(find.text('准备预约此座位'), findsNothing);
    } else {
      debugPrint('图书馆只读 seats=NOT_APPLICABLE reason=no_time_slot');
    }
    await tap(find.byTooltip('返回'));
    await tap(find.widgetWithText(Card, '我的预约'));
    await loaded(FeatureQueryView.libbookBookings);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
    debugPrint('图书馆只读 完成 businessWrites=0');
  });
}
