import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import '../../../integration_test/synthetic/grades/watch/backend.dart';

void main() {
  testWidgets('成绩基线保存失败不打断在线首页，也不显示内部缓存故障', (tester) async {
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: GradeWatchBackend(),
        credentialVault: MemoryCredentialVault(),
        gradeScoreStore: _FailingBaselineStore(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('成绩可在线查看，本机变化记录暂不可用'), findsNothing);
    expect(find.text('合成今日课程'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-grade-update')), findsNothing);
  });
  testWidgets('清除账号时成绩文件损坏也能退出，并明确提示本机未完全清除', (tester) async {
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: GradeWatchBackend(),
        credentialVault: MemoryCredentialVault(),
        gradeScoreStore: _FailingClearStore(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    final button = find.text('退出并清除本机账号');
    await tester.scrollUntilVisible(
      button,
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey<String>('feature-pages')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '退出并清除'));
    await tester.pumpAndSettle();
    expect(find.byType(UbaaLoginView), findsOneWidget);
    expect(find.text('本机数据未能完全清除，请稍后重试。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('手机普通成绩提醒沿旧版横排操作，不额外占一行', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final backend = GradeWatchBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    backend.score = '90';
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('home-grade-update'))).height,
      lessThanOrEqualTo(112),
    );
    expect(
      tester.getCenter(find.text('查看')).dy,
      tester.getCenter(find.text('忽略')).dy,
    );
  });
  testWidgets('首页首次无提醒，变化在内容顶部显示，忽略和查看分别消费', (tester) async {
    final backend = GradeWatchBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    final banner = find.byKey(const ValueKey('home-grade-update'));
    expect(banner, findsNothing);
    backend.score = '90';
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('合成数学课程 成绩已更新'), findsOneWidget);
    expect(
      tester.getTopLeft(banner).dy,
      lessThan(tester.getTopLeft(find.text('今日课表')).dy),
    );
    expect(
      tester.getBottomRight(banner).dy,
      lessThan(tester.getTopLeft(find.text('合成今日课程')).dy),
    );
    await tester.tap(find.widgetWithText(TextButton, '忽略'));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    backend.score = '100';
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '查看'));
    await tester.pumpAndSettle();
    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    expect(
      shell.snapshots[FeatureId.grades]!.readContext!.query!.term,
      '2026-2027-1',
    );
    expect(find.text('本学期'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });
  testWidgets('成绩提醒实际WebVPN进入首页混合路线说明，首次该路线不误报', (tester) async {
    final backend = GradeWatchBackend();
    await tester.pumpWidget(
      UbaaFlutterApp(
        backend: backend,
        credentialVault: MemoryCredentialVault(),
      ),
    );
    await tester.pumpAndSettle();
    backend.gradeRoute = ConnectionMode.webvpn;
    backend.score = '90';
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-grade-update')), findsNothing);
    expect(find.byTooltip('实际路线：混合'), findsOneWidget);
    await tester.tap(find.byTooltip('实际路线：混合'));
    await tester.pumpAndSettle();
    expect(find.text('成绩检查：WebVPN'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pumpAndSettle();
    backend.score = '100';
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('实际路线：混合'), findsOneWidget);
    await tester.tap(find.byTooltip('实际路线：混合'));
    await tester.pumpAndSettle();
    expect(find.text('成绩更新：WebVPN'), findsOneWidget);
  });
}

class _FailingBaselineStore implements GradeScoreStore {
  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) async => throw const FileSystemException('合成缓存不可用');
  @override
  Future<void> clearAccount(String account) async {}
}

class _FailingClearStore implements GradeScoreStore {
  final delegate = MemoryGradeScoreStore();
  @override
  Future<GradeScoreBaseline?> update(
    String account,
    ConnectionMode route,
    GradeScoreBaseline value,
  ) => delegate.update(account, route, value);
  @override
  Future<void> clearAccount(String account) async {
    throw const FormatException('合成基线损坏');
  }
}
