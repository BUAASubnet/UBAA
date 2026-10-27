import '../../navigation.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 生产教室只读与原生查询；只输出状态和数量，不截图或执行业务写入。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产空教室旧表格与校区楼栋节次查询只读', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-e3a-') ||
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
        .snapshots[FeatureId.classroom]!;
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 150));
    }

    Future<void> loaded({int? previous, int? campus}) async {
      await waitFor(
        () =>
            snapshot().status != FeatureLoadStatus.idle &&
            snapshot().status != FeatureLoadStatus.loading &&
            (previous == null ||
                snapshot().readContext?.requestRevision != previous) &&
            (campus == null || snapshot().readContext?.query?.campus == campus),
      );
      final s = snapshot();
      debugPrint(
        '教室只读 status=${s.status.name} route=${s.resolvedRoute?.name} count=${s.details.length} campus=${s.readContext?.query?.campus} error=${s.error?.code.name}',
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
    await tap(find.widgetWithText(Card, FeatureId.classroom.title));
    await loaded();
    expect(
      find
          .byKey(const ValueKey<String>('feature-search-field'))
          .evaluate()
          .isNotEmpty,
      isTrue,
    );
    if (snapshot().details.isNotEmpty) {
      final first = snapshot().details.first;
      final before = snapshot().readContext?.requestRevision;
      expect(find.text('14').evaluate().isNotEmpty, isTrue);
      await tap(find.text(first.title).first);
      expect(find.byType(AlertDialog).evaluate().isNotEmpty, isTrue);
      expect(snapshot().readContext?.requestRevision, before);
      await tap(find.widgetWithText(TextButton, '关闭'));
      debugPrint('教室只读 localDetail=true extraReads=0');
    }
    // 校区与日期在宽屏正文切换；楼层只剩正文楼栋标签的本地过滤，节次不再可选。
    final campus = find.descendant(
      of: find.byType(SegmentedButton<int>),
      matching: find.text('沙河'),
    );
    if (campus.evaluate().isEmpty) {
      debugPrint('教室只读 campus=NOT_APPLICABLE reason=narrow_layout');
    } else {
      final previous = snapshot().readContext?.requestRevision;
      await tap(campus);
      await loaded(previous: previous, campus: 2);
      expect(snapshot().readContext?.query?.floorId, isNull);
      expect(snapshot().readContext?.query?.section, isNull);
      final buildings = snapshot().details
          .map((d) => d.presentation)
          .whereType<ClassroomPresentation>()
          .map((p) => p.floorName)
          .where((name) => name.trim().isNotEmpty)
          .toSet();
      if (buildings.isNotEmpty) {
        final before = snapshot().readContext?.requestRevision;
        await tap(find.widgetWithText(FilterChip, buildings.first));
        expect(snapshot().readContext?.requestRevision, before);
        await tap(find.widgetWithText(FilterChip, buildings.first));
        debugPrint('教室只读 campus=true buildingChip=true extraReads=0');
      } else {
        debugPrint('教室只读 campus=true buildingChip=NOT_APPLICABLE');
      }
    }
    expect(tester.takeException(), isNull);
    debugPrint('教室只读 完成 businessWrites=0');
  });
}
