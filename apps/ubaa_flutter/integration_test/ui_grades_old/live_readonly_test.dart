import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 真实成绩只读：不截图、不输出学期课程分数，不进入业务写入。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产成绩旧版全学期统计与三视图只读', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-') ||
        !{'direct', 'webvpn'}.contains(route)) {
      throw StateError('必须显式提供生产只读开关、隔离配置和预期路线');
    }
    Widget? app;
    await bootstrapUbaaFlutterApp(runApplication: (value) => app = value);
    await tester.pumpWidget(app!);
    Future<void> waitFor(bool Function() ready) async {
      for (var i = 0; i < 600 && !ready(); i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(ready(), isTrue, reason: '生产只读状态未在限定时间完成');
    }

    await waitFor(
      () =>
          find.byType(UbaaMainShell).evaluate().isNotEmpty ||
          find.byType(UbaaLoginView).evaluate().isNotEmpty,
    );
    expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
    UbaaMainShell shell() =>
        tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    Future<void> tap(Finder finder) async {
      expect(finder.evaluate().isNotEmpty, isTrue, reason: '只读入口未出现');
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 250));
    }

    Future<void> loaded(FeatureQueryView view) async {
      await waitFor(() {
        final value = shell().snapshots[FeatureId.grades]!;
        return (value.readContext?.query?.view ?? FeatureQueryView.summary) ==
                view &&
            value.status != FeatureLoadStatus.idle &&
            value.status != FeatureLoadStatus.loading;
      });
      final value = shell().snapshots[FeatureId.grades]!;
      debugPrint(
        '成绩旧版只读 view=${view.name} status=${value.status.name} route=${value.resolvedRoute?.name} count=${value.details.length} error=${value.error?.code.name}',
      );
      expect(
        value.status == FeatureLoadStatus.success ||
            value.status == FeatureLoadStatus.empty,
        isTrue,
      );
      expect(value.resolvedRoute?.name, route);
      expect(value.overview is GradesTermOverview, isTrue);
      await tester.pump(const Duration(milliseconds: 250));
    }

    await tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.apps_outlined),
      ),
    );
    await tap(find.widgetWithText(Card, FeatureId.grades.title));
    await loaded(FeatureQueryView.summary);
    GradesAggregate? aggregate;
    Object? aggregateFailure;
    final pending = shell().onLoadAllGrades!(false).then<void>(
      (value) {
        aggregate = value;
      },
      onError: (Object error) {
        aggregateFailure = error;
      },
    );
    await waitFor(() => aggregate != null || aggregateFailure != null);
    await pending;
    expect(aggregateFailure == null, isTrue);
    final result = aggregate!;
    debugPrint(
      '成绩旧版只读 aggregateComplete=${result.isComplete} loadedTerms=${result.loadedTerms} totalTerms=${result.terms.length} count=${result.statistics.courseCount} error=${result.error?.code.name}',
    );
    expect(result.isComplete, isTrue);
    expect(
      result.terms.every(
        (t) => t.resolvedRoute?.name == route && t.overview != null,
      ),
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find
          .byTooltip(route == 'direct' ? '实际路线：直连' : '实际路线：WebVPN')
          .evaluate()
          .isNotEmpty,
      isTrue,
    );
    expect(find.byType(TextField).evaluate().isEmpty, isTrue);
    for (final (label, view) in [
      ('待出成绩', FeatureQueryView.gradesMissing),
      ('已出成绩', FeatureQueryView.gradesScored),
      ('全部成绩', FeatureQueryView.summary),
    ]) {
      await tap(find.byTooltip('搜索与筛选'));
      await tap(find.byType(DropdownButton<FeatureQueryView>));
      await tap(find.text(label).last);
      await tap(find.text('应用筛选'));
      await loaded(view);
      await tap(find.widgetWithText(TextButton, '完成'));
    }
    // 当前学期为空时，从已实际读取的学期中选择一个非空项，仍只使用原查询。
    if (shell().snapshots[FeatureId.grades]!.details.isEmpty) {
      final candidates = result.terms.where(
        (term) => term.overview?.grades.isNotEmpty == true,
      );
      if (candidates.isNotEmpty) {
        await tap(find.byTooltip('搜索与筛选'));
        await tap(find.widgetWithText(TextField, '学期编码'));
        await tester.enterText(
          find.widgetWithText(TextField, '学期编码'),
          candidates.first.code,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 250));
        await tap(find.text('应用筛选'));
        await loaded(FeatureQueryView.summary);
        await tap(find.widgetWithText(TextButton, '完成'));
      }
    }
    var detailOpened = false;
    if (shell().snapshots[FeatureId.grades]!.details.isNotEmpty) {
      final revision =
          shell().snapshots[FeatureId.grades]!.readContext?.requestRevision;
      await tap(find.byIcon(Icons.book).first);
      expect(find.byType(AlertDialog).evaluate().isNotEmpty, isTrue);
      await tap(find.text('更多信息').last);
      await tap(find.widgetWithText(TextButton, '关闭'));
      expect(
        shell().snapshots[FeatureId.grades]!.readContext?.requestRevision,
        revision,
      );
      detailOpened = true;
    }
    debugPrint(
      '成绩旧版只读 localDetail=$detailOpened extraRead=false businessWrites=0 完成',
    );
  });
}
