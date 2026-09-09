import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 仅生产只读用途及表单浏览；不填个人资料，不prepare/commit，不截图。
void main() {
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
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(f);
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
