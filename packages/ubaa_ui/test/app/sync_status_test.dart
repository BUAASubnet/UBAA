import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/shared/sync_status.dart';

void main() {
  test('iOS、Android 和 OHOS 使用触屏刷新，桌面保留按钮', () {
    for (final name in ['iOS', 'android', 'ohos']) {
      expect(uiIsTouchPlatformName(name), isTrue);
    }
    for (final name in ['macOS', 'windows', 'linux']) {
      expect(uiIsTouchPlatformName(name), isFalse);
    }
  });
  testWidgets('短请求不闪烁，持续请求延迟显示并在结束后恢复时间', (tester) async {
    Future<void> mount(bool busy) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UiSyncStatus(
            busy: busy,
            updatedAt: DateTime(2026, 10, 31, 9, 30),
          ),
        ),
      ),
    );
    await mount(true);
    await tester.pump(const Duration(milliseconds: 399));
    expect(find.text('更新中'), findsNothing);
    await mount(false);
    await tester.pump(const Duration(milliseconds: 401));
    expect(find.text('更新中'), findsNothing);
    await mount(true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('更新中'), findsOneWidget);
    await mount(false);
    await tester.pumpAndSettle();
    expect(find.textContaining('09:30'), findsOneWidget);
  });
  testWidgets('主动刷新立即反馈且阻止按钮重复提交', (tester) async {
    final gate = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UiSyncStatus(
            busy: false,
            onRefresh: () {
              calls++;
              return gate.future;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    expect(find.text('更新中'), findsOneWidget);
    await tester.tap(find.byTooltip('刷新'));
    expect(calls, 1);
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNotNull,
    );
  });
}
