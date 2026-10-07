import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 生产阳光首页与记录只读复验，不截图、不准备或执行提交。
void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产阳光旧首页与记录分页双路线只读复验', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-') ||
        (route != 'direct' && route != 'webvpn')) {
      throw StateError('必须显式提供生产只读开关、隔离配置和预期路线');
    }
    Widget? app;
    await bootstrapUbaaFlutterApp(runApplication: (value) => app = value);
    await tester.pumpWidget(app!);
    Future<void> waitFor(bool Function() ready, String reason) async {
      for (var step = 0; step < 480 && !ready(); step++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(ready(), isTrue, reason: reason);
    }

    await waitFor(
      () =>
          find.byType(UbaaMainShell).evaluate().isNotEmpty ||
          find.byType(UbaaLoginView).evaluate().isNotEmpty,
      '隔离生产会话未能恢复',
    );
    expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
    FeatureSnapshot snapshot() => tester
        .widget<UbaaMainShell>(find.byType(UbaaMainShell))
        .snapshots[FeatureId.ygdk]!;
    Future<void> tap(Finder finder) async {
      expect(finder.evaluate().isNotEmpty, isTrue, reason: '只读入口未出现');
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 400));
      expect(finder.hitTestable().evaluate().isNotEmpty, isTrue);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> loaded(FeatureQueryView view, {int? page}) async {
      await waitFor(() {
        final value = snapshot();
        return value.readContext?.query?.view == view &&
            (page == null || value.readContext?.query?.page == page) &&
            value.status != FeatureLoadStatus.idle &&
            value.status != FeatureLoadStatus.loading;
      }, '阳光只读查询未在限定时间完成');
      final value = snapshot();
      debugPrint(
        '阳光只读 view=${view.name} status=${value.status.name} '
        'route=${value.resolvedRoute?.name} count=${value.details.length} '
        'displayPage=${value.pagination?.page} error=${value.error?.code.name}',
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
        matching: find.byIcon(Icons.auto_awesome_outlined),
      ),
    );
    await tap(find.widgetWithText(Card, FeatureId.ygdk.title));
    await loaded(FeatureQueryView.summary);
    final overview = snapshot().overview as YgdkOverview;
    expect(overview.records != null, isTrue);
    expect(overview.records?.errorCode == null, isTrue);
    expect(overview.records?.page, 1);
    debugPrint(
      '阳光只读 homeRecords=${overview.records!.content.length} '
      'page=${overview.records!.page} error=${overview.records!.errorCode}',
    );
    expect(find.byType(TextField).evaluate().isEmpty, isTrue);
    if (overview.records!.content.isNotEmpty) {
      final item = overview.records!.content.first;
      final revision = snapshot().readContext?.requestRevision;
      await tap(find.widgetWithText(Card, item.itemName ?? '打卡记录').first);
      expect(find.text('记录详情').evaluate().isNotEmpty, isTrue);
      expect(snapshot().readContext?.requestRevision == revision, isTrue);
      await tap(find.text('关闭'));
      debugPrint('阳光只读 localDetail=true extraRead=false');
    } else {
      debugPrint('阳光只读 localDetail=未执行 reason=当前无记录');
    }
    final revision = snapshot().readContext?.requestRevision;
    await tap(find.byTooltip('新增打卡'));
    expect(
      find.widgetWithText(AppBar, '填写阳光打卡信息').evaluate().isNotEmpty,
      isTrue,
    );
    expect(find.byType(AlertDialog).evaluate().isEmpty, isTrue);
    expect(
      find
          .byTooltip('实际路线：${route == 'direct' ? '直连' : 'WebVPN'}')
          .evaluate()
          .isNotEmpty,
      isTrue,
    );
    await tap(find.text('选择运动项目'));
    expect(find.byType(ListTile).evaluate().isNotEmpty, isTrue);
    await tap(find.text('关闭'));
    await tap(find.text('取消'));
    expect(snapshot().readContext?.requestRevision == revision, isTrue);
    debugPrint(
      '阳光只读 independentForm=true projectPicker=true extraRead=false prepare=false',
    );
    await tap(find.byTooltip('搜索与筛选'));
    await tap(find.byType(DropdownButton<FeatureQueryView>));
    await tap(find.text('记录列表').last);
    Future<void> edit(String label, String value) async {
      final field = find.widgetWithText(TextField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pump();
    }

    await edit('页码', '2');
    await edit('每页数量', '5');
    await tap(find.text('应用筛选'));
    await loaded(FeatureQueryView.ygdkRecords, page: 2);
    expect(
      snapshot().details.every((d) => d.presentation is YgdkRecordPresentation),
      isTrue,
    );
    await tap(find.widgetWithText(TextButton, '完成'));
    await tap(find.byTooltip('搜索与筛选'));
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '页码'))
          .controller!
          .text,
      '2',
    );
    await tap(find.widgetWithText(TextButton, '完成'));
    await tap(find.byTooltip('上一页'));
    await loaded(FeatureQueryView.ygdkRecords, page: 1);
    expect(find.byType(TextField).evaluate().isEmpty, isTrue);
    debugPrint('生产阳光旧首页与记录分页完成，businessWrites=0');
  });
}
