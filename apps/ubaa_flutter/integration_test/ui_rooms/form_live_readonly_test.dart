import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 仅生产只读用途及表单浏览；不填个人资料，不prepare/commit，不截图。
void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产研讨室用途独立读取及表单返回只读', (tester) async {
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !config.contains('UBAA-ui-readonly-P5B-') ||
        !Directory(config).isAbsolute ||
        !['direct', 'webvpn'].contains(route)) {
      throw StateError('需要本批独立配置和显式真实只读开关');
    }
    Widget? app;
    await bootstrapUbaaFlutterApp(runApplication: (value) => app = value);
    await tester.pumpWidget(app!);
    Future<void> wait(bool Function() ready) async {
      for (var i = 0; i < 480 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(ready(), isTrue, reason: '真实只读状态未完成，未执行写入');
    }

    await wait(
      () =>
          find.byType(UbaaMainShell).evaluate().isNotEmpty ||
          find.byType(UbaaLoginView).evaluate().isNotEmpty,
    );
    expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
    UbaaMainShell shell() => tester.widget<UbaaMainShell>(
      find.byType(UbaaMainShell, skipOffstage: false),
    );
    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        f.hitTestable().evaluate().isNotEmpty,
        isTrue,
        reason: '只读操作目标尚不可点击',
      );
      await tester.tap(f);
      await tester.pump(const Duration(milliseconds: 400));
      // 首帧建立弹出路线，下一帧完成其转场后再定位菜单项。
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tap(find.byIcon(Icons.auto_awesome_outlined));
    await tap(find.widgetWithText(Card, FeatureId.cgyy.title));
    await tap(find.widgetWithText(Card, '预约研讨室'));
    await wait(() {
      final value = shell().snapshots[FeatureId.cgyy]!;
      return value.readContext?.query?.view == FeatureQueryView.cgyyDayInfo &&
          value.status != FeatureLoadStatus.loading;
    });
    debugPrint('只读进度：日时段读取结束');
    final day = shell().snapshots[FeatureId.cgyy]!;
    expect(
      day.status == FeatureLoadStatus.success ||
          day.status == FeatureLoadStatus.empty,
      isTrue,
    );
    expect(day.resolvedRoute?.name == route, isTrue);
    final result = await tester.runAsync(
      () => shell().onLoadCgyyPurposes!(false),
    );
    expect(
      result != null &&
          result.error == null &&
          result.resolvedRoute?.name == route,
      isTrue,
    );
    final options = result!.details
        .map((d) => d.presentation)
        .whereType<CgyyPurposePresentation>()
        .toList();
    expect(options.isNotEmpty && options.every((p) => p.key > 0), isTrue);
    expect(identical(shell().snapshots[FeatureId.cgyy], day), isTrue);
    debugPrint('只读进度：用途选项读取结束');
    if (const bool.fromEnvironment('UBAA_ROOM_QUERY_CONTROLS')) {
      expect(find.byType(FilterChip).evaluate().isEmpty, isTrue);
      await tap(find.byTooltip('搜索与筛选'));
      final siteFinder = find.byKey(const ValueKey('cgyy-choice-楼栋 / 楼层'));
      final dateFinder = find.byKey(const ValueKey('cgyy-choice-预约日期'));
      expect(
        siteFinder.evaluate().isNotEmpty && dateFinder.evaluate().isNotEmpty,
        isTrue,
      );
      final original = shell().snapshots[FeatureId.cgyy];
      await tap(find.widgetWithText(TextButton, '完成'));
      expect(identical(shell().snapshots[FeatureId.cgyy], original), isTrue);
      await tap(find.byTooltip('搜索与筛选'));
      final datePicker = tester.widget<DropdownButton<String>>(dateFinder);
      final otherDates = datePicker.items!
          .map((i) => i.value)
          .whereType<String>()
          .where((value) => value != datePicker.value)
          .toList();
      expect(otherDates.isNotEmpty, isTrue, reason: '没有其他可用日期，本次日期切换未执行');
      final nextDate = otherDates.first;
      debugPrint('只读进度：开始按需日期切换');
      await tap(dateFinder);
      await tap(find.text(nextDate).last);
      await wait(() {
        final current = shell().snapshots[FeatureId.cgyy]!;
        return current.readContext?.query?.date
                    ?.toIso8601String()
                    .split('T')
                    .first ==
                nextDate &&
            current.status != FeatureLoadStatus.loading;
      });
      expect(
        shell().snapshots[FeatureId.cgyy]!.status == FeatureLoadStatus.success,
        isTrue,
      );
      debugPrint('只读进度：日期切换结束');
      final sitePicker = tester.widget<DropdownButton<int>>(siteFinder);
      final otherSites = sitePicker.items!
          .where((item) => item.value != sitePicker.value && item.value != null)
          .toList();
      expect(otherSites.isNotEmpty, isTrue, reason: '没有其他站点，本次站点切换未执行');
      final nextSite = otherSites.first.value!;
      debugPrint('只读进度：开始按需站点切换');
      await tap(siteFinder);
      final menuItem = find.byWidgetPredicate(
        (w) => w is DropdownMenuItem<int> && w.value == nextSite,
      );
      await tap(
        find.descendant(of: menuItem.last, matching: find.byType(Text)).last,
      );
      await wait(() {
        final current = shell().snapshots[FeatureId.cgyy]!;
        return current.readContext?.query?.siteId == nextSite &&
            current.status != FeatureLoadStatus.loading;
      });
      final current = shell().snapshots[FeatureId.cgyy]!;
      expect(
        current.status == FeatureLoadStatus.success &&
            current.resolvedRoute?.name == route,
        isTrue,
      );
      expect(
        current.readContext?.query?.date?.toIso8601String().split('T').first ==
            nextDate,
        isTrue,
      );
      await tap(find.widgetWithText(TextButton, '完成'));
      expect(find.byType(FilterChip).evaluate().isEmpty, isTrue);
      expect(find.widgetWithText(TextButton, '完成').evaluate().isEmpty, isTrue);
      debugPrint(
        '研讨室按需查询 route=$route panel=PASS dateSwitch=PASS siteSwitch=PASS preservedDate=PASS writes=0',
      );
      return;
    }
    final candidates = day.details
        .where(
          (d) =>
              d.presentation is CgyySlotPresentation &&
              d.actions.whereType<CgyyReserveAction>().any(
                (a) => a.eligibility == ActionEligibility.allowed,
              ),
        )
        .toList();
    if (candidates.isEmpty) {
      debugPrint(
        '研讨室只读 route=$route purposeCount=${options.length} form=NOT_APPLICABLE-no-allowed-slot writes=0',
      );
      return;
    }
    final slot = candidates.first.presentation! as CgyySlotPresentation;
    final days = day.details
        .map((d) => d.presentation)
        .whereType<CgyyDayPresentation>()
        .toList();
    expect(days.length == 1, isTrue);
    final times = days.single.timeSlots
        .where((t) => t.id == slot.timeId)
        .toList();
    expect(times.length == 1, isTrue);
    await tap(
      find.byTooltip(
        '${slot.spaceName} ${times.single.beginTime}–${times.single.endTime}',
      ),
    );
    await tap(find.text('下一步'));
    await wait(
      () => find
          .widgetWithText(OutlinedButton, options.first.name)
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byType(AlertDialog).evaluate().isEmpty, isTrue);
    expect(identical(shell().snapshots[FeatureId.cgyy], day), isTrue);
    await tap(find.widgetWithText(OutlinedButton, options.first.name));
    expect(find.text('选择活动类型').evaluate().isNotEmpty, isTrue);
    await tap(find.text('关闭'));
    await tap(find.text('返回修改时段'));
    expect(find.text('下一步').evaluate().isNotEmpty, isTrue);
    debugPrint(
      '研讨室只读 route=$route purposeCount=${options.length} sourceFallback=${options.any((p) => p.isStaticFallback)} form=PASS draftReturn=PASS writes=0',
    );
  });
}
