import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'backend.dart';
import '../parity_test.dart' as old;

/// 三个显式查询通过真实页面操作；业务只使用内存 backend。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  for (final brightness in Brightness.values) {
    testWidgets('签到三视图草稿与返回 ${brightness.name}', (tester) async {
      final backend = AcademicOldBackend();
      await old.mount(tester, backend, brightness, FeatureId.signin);
      FeatureSnapshot snapshot() => tester
          .widget<UbaaMainShell>(find.byType(UbaaMainShell))
          .snapshots[FeatureId.signin]!;
      int reads() => backend.academicReads
          .where((read) => read.$1 == FeatureId.signin)
          .length;
      Future<void> shot(String name, String steps) => old.capture(
        binding,
        tester,
        '${brightness.name}-signin-query-$name',
        steps,
      );
      Future<void> panel() => old.tap(
        tester,
        find.byKey(const ValueKey<String>('feature-filter-button')),
      );
      // 状态标签点选即发出派生视图查询，没有草稿和“应用”步骤。
      Future<void> select(String label) =>
          old.tap(tester, find.widgetWithText(ChoiceChip, label));
      final search = find.byKey(const ValueKey<String>('feature-search-field'));

      expect(snapshot().details.length, 4);
      expect(search, findsOneWidget);
      final initialReads = reads();
      await panel();
      expect(reads(), initialReads);
      await shot('draft', '打开筛选面板不读取，原全部结果保持');
      await select('可签到');
      expect(reads(), initialReads + 1);
      await old.closePanel(tester);
      expect(
        snapshot().readContext?.query?.view,
        FeatureQueryView.signinPending,
      );
      expect(snapshot().details.length, 1);
      expect(snapshot().details.single.title, '合成可签到课程');
      expect(snapshot().resolvedRoute, ConnectionMode.direct);
      await shot('pending', '显式可签到视图仅原allowed，未知及缺目标不误归类');
      final detailReads = reads();
      await old.tap(tester, find.byTooltip('课程详情'));
      await shot('detail', '原课程时间与低频字段本地详情，不新增读取或准备');
      await old.tap(tester, find.widgetWithText(TextButton, '关闭'));
      expect(reads(), detailReads);
      await old.tap(tester, find.byTooltip('返回'));
      await old.tap(tester, find.widgetWithText(Card, '课堂签到'));
      expect(reads(), detailReads);
      expect(
        snapshot().readContext?.query?.view,
        FeatureQueryView.signinPending,
      );
      await shot('back', '返回课程与作业再进入保持已应用视图');

      for (final (label, view, titles) in [
        ('已签到', FeatureQueryView.signinCompleted, ['合成已签到课程']),
        (
          '全部',
          FeatureQueryView.summary,
          ['合成可签到课程', '合成已签到课程', '合成未知状态课程', '合成缺少目标课程'],
        ),
      ]) {
        await panel();
        await select(label);
        await old.closePanel(tester);
        expect(snapshot().readContext?.query?.view, view);
        expect(snapshot().details.map((detail) => detail.title), titles);
        expect(snapshot().resolvedRoute, ConnectionMode.direct);
        expect(find.byTooltip('关闭筛选').hitTestable(), findsNothing);
        await shot(view.name.toLowerCase(), '显式$label结果与原查询匹配，面板已关闭');
        final count = reads();
        await old.tap(tester, find.byTooltip('刷新当前查询'));
        expect(reads(), count + 1);
        expect(backend.academicReads.last.$2.view, view);
        expect(snapshot().details.map((detail) => detail.title), titles);
      }
      expect(backend.preparedSignin, isEmpty);
      expect(backend.commitCalls, 0);
    });
  }
}
