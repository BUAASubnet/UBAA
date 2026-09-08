import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../integration_test/ui_coursework/backend.dart';

void main() {
  testWidgets('真实App控制器单项返回后换搜索保留其他父作业', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 874);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> ensure(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          240,
          scrollable: find
              .byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              )
              .last,
          maxScrolls: 60,
        );
      }
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    Future<void> tap(Finder finder) async {
      await ensure(finder);
      expect(finder.hitTestable(), findsOneWidget);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> panel() async {
      if (find.text('完成').evaluate().isEmpty) {
        await tap(find.byTooltip('搜索与筛选'));
      }
    }

    Future<void> closePanel() async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tap(find.text('完成'));
    }

    Future<void> search(String value) async {
      await panel();
      final field = find.widgetWithText(TextField, '筛选详情');
      await ensure(field);
      await tester.enterText(field, value);
      await closePanel();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: CourseworkBackend(),
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'synthetic-coursework',
    );
    await tester.enterText(find.byType(TextField).at(1), 'synthetic-password');
    FocusManager.instance.primaryFocus?.unfocus();
    await tap(find.widgetWithText(FilledButton, '登录'));
    await tap(find.widgetWithText(NavigationDestination, '普通功能'));
    await tap(find.widgetWithText(Card, FeatureId.judge.title));
    await panel();
    await tap(find.text('包含已过期作业'));
    await tap(find.text('应用筛选'));
    await search('judge-a');
    await tap(find.byTooltip('查看作业详情'));
    await tap(find.byTooltip('返回'));
    await search('judge-b');
    await panel();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '筛选详情'))
          .controller!
          .text,
      'judge-b',
    );
    await closePanel();
    await tap(
      find.byKey(const ValueKey(('judge-selection', 'judge-b', 'shared'))),
    );
    expect(find.text('已选择 1 份作业'), findsOneWidget);
  });
}
