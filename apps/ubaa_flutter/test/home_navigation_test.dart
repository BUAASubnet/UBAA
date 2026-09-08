import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../integration_test/ui_home/backend.dart';

void main() {
  testWidgets('首页混合路线说明在短窗口可滚动并关闭', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(740, 420);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final backend = HomeBackend()..mixedRoutes = true;
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('实际路线：混合'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    expect(find.text('连接路线'), findsNothing);
  });
  testWidgets('首页路线按已显示的实际来源聚合，不能显示默认策略', (tester) async {
    final backend = HomeBackend()..mixedRoutes = true;
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('实际路线：混合'), findsOneWidget);
    await tester.tap(find.byTooltip('实际路线：混合'));
    await tester.pumpAndSettle();
    expect(find.text('当前页面：直连与WebVPN'), findsOneWidget);
    expect(find.text('研讨室：WebVPN'), findsOneWidget);
    expect(find.text('今日课表：直连'), findsOneWidget);
  });
  testWidgets('首页恢复六来源并按旧今日课程时间排序，点击待办直达原作业', (tester) async {
    final backend = HomeBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    for (final title in [
      '合成签到待办',
      '合成博雅待办',
      '合成SPOC待办',
      '合成希冀待办',
      '合成研讨室待办',
      '本周阳光打卡未达标',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        200,
        scrollable: find.byType(Scrollable).hitTestable().last,
        maxScrolls: 25,
      );
      expect(find.text(title), findsOneWidget);
    }
    await tester.drag(
      find.byType(Scrollable).hitTestable().last,
      const Offset(0, 5000),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('合成上午课程')).dy,
      lessThan(tester.getTopLeft(find.text('合成下午课程')).dy),
    );
    await tester.scrollUntilVisible(
      find.text('合成SPOC待办'),
      180,
      scrollable: find.byType(Scrollable).hitTestable().last,
    );
    await tester.tap(find.text('合成SPOC待办'));
    await tester.pumpAndSettle();
    expect(backend.homeQueries.last.$2.view, FeatureQueryView.spocDetail);
    expect(backend.homeQueries.last.$2.assignmentId, 'spoc-a');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsNothing);
    expect(find.text('合成SPOC待办'), findsOneWidget);
    await tester.drag(
      find.byType(Scrollable).hitTestable().last,
      const Offset(0, 5000),
    );
    await tester.pumpAndSettle();
    expect(find.text('今日课表'), findsOneWidget);
    expect(backend.commitCalls, 0);
  });
  testWidgets('首页课堂签到只使用原typed目标准备并取消，阳光提醒可关闭', (tester) async {
    final backend = HomeBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, '签到'),
      200,
      scrollable: find.byType(Scrollable).hitTestable().last,
    );
    await tester.tap(find.widgetWithText(FilledButton, '签到'));
    await tester.pumpAndSettle();
    expect(backend.preparedSignin, ['signin-target']);
    await tester.tap(find.widgetWithText(OutlinedButton, '取消'));
    await tester.pumpAndSettle();
    expect(backend.commitCalls, 0);
    await tester.scrollUntilVisible(
      find.text('本周阳光打卡未达标'),
      200,
      scrollable: find.byType(Scrollable).hitTestable().last,
      maxScrolls: 20,
    );
    await tester.ensureVisible(find.text('本周阳光打卡未达标'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本周阳光打卡未达标'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(SwitchListTile, '首页提醒'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, '首页提醒'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '首页提醒'))
          .value,
      isFalse,
    );
    final count = backend.homeQueries.length;
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('本周阳光打卡未达标'), findsNothing);
    expect(backend.homeQueries, hasLength(count));
  });
}
