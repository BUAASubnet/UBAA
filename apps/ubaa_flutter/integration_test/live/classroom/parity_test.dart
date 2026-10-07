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

    Future<void> edit(String label, String value) async {
      final field = find.widgetWithText(TextField, label);
      await tap(field);
      await tester.enterText(field, value);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller!.text == value, isTrue);
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

    await tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.apps_outlined),
      ),
    );
    await tap(find.widgetWithText(Card, FeatureId.classroom.title));
    await loaded();
    expect(find.byType(TextField).evaluate().isEmpty, isTrue);
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
    await tap(find.byTooltip('搜索与筛选'));
    await tap(find.byType(DropdownButton<int>));
    await tap(find.text('沙河').last);
    final previous = snapshot().readContext?.requestRevision;
    await tap(find.widgetWithText(FilledButton, '应用筛选'));
    await loaded(previous: previous, campus: 2);
    await tap(find.widgetWithText(TextButton, '完成'));
    final targets = snapshot().details
        .where((d) => d.presentation is ClassroomPresentation)
        .map((d) => d.presentation! as ClassroomPresentation)
        .where(
          (p) =>
              p.floorId.trim().isNotEmpty &&
              p.sectionTokens.any(
                (s) => int.tryParse(s) != null && int.parse(s) > 0,
              ),
        )
        .toList();
    if (targets.isNotEmpty) {
      final target = targets.first;
      final section = target.sectionTokens.firstWhere(
        (s) => int.tryParse(s) != null && int.parse(s) > 0,
      );
      await tap(find.byTooltip('搜索与筛选'));
      await edit('楼层', target.floorId);
      await edit('节次', section);
      final before = snapshot().readContext?.requestRevision;
      await tap(find.widgetWithText(FilledButton, '应用筛选'));
      await loaded(previous: before, campus: 2);
      expect(
        snapshot().details.every(
          (d) =>
              d.presentation is ClassroomPresentation &&
              (d.presentation! as ClassroomPresentation).floorId ==
                  target.floorId &&
              (d.presentation! as ClassroomPresentation).sectionTokens.contains(
                section,
              ),
        ),
        isTrue,
      );
      await tap(find.widgetWithText(TextButton, '完成'));
      await tap(find.byTooltip('搜索与筛选'));
      expect(
        tester
                .widget<TextField>(find.widgetWithText(TextField, '楼层'))
                .controller!
                .text ==
            target.floorId,
        isTrue,
      );
      expect(
        tester
                .widget<TextField>(find.widgetWithText(TextField, '节次'))
                .controller!
                .text ==
            section,
        isTrue,
      );
      await tap(find.widgetWithText(TextButton, '完成'));
      debugPrint('教室只读 floorSection=true retainedDraft=true');
    } else {
      debugPrint('教室只读 floorSection=NOT_APPLICABLE reason=no_usable_option');
    }
    expect(tester.takeException(), isNull);
    debugPrint('教室只读 完成 businessWrites=0');
  });
}
