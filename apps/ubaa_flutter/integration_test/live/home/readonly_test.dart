import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 首页生产只读：只记录状态、路线和数量，不拍摄个人页面或准备写入。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产首页六来源与实际路线只读复验', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-') ||
        (route != 'direct' && route != 'webvpn')) {
      throw StateError('必须显式提供生产只读开关、隔离配置和预期路线');
    }
    final elapsed = Stopwatch()..start();
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
      '隔离会话未恢复',
    );
    expect(find.byType(UbaaMainShell).evaluate().isNotEmpty, isTrue);
    debugPrint('首页计时 shell_ready_ms=${elapsed.elapsedMilliseconds}');
    UbaaMainShell shell() =>
        tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    for (final feature in [
      FeatureId.schedule,
      FeatureId.signin,
      FeatureId.spoc,
      FeatureId.judge,
      FeatureId.ygdk,
    ]) {
      await waitFor(() {
        final status = shell().homeSnapshots![feature]!.status;
        return status != FeatureLoadStatus.idle &&
            status != FeatureLoadStatus.loading;
      }, '首页默认来源未在限定时间完成');
      final value = shell().homeSnapshots![feature]!;
      debugPrint(
        '首页只读 feature=${feature.name} status=${value.status.name} route=${value.resolvedRoute?.name} count=${value.details.length} error=${value.error?.code.name} observed_ms=${elapsed.elapsedMilliseconds}',
      );
      expect(
        value.status == FeatureLoadStatus.success ||
            value.status == FeatureLoadStatus.empty,
        isTrue,
      );
      expect(value.resolvedRoute?.name, route);
    }
    for (final feature in [
      FeatureId.exam,
      FeatureId.grades,
      FeatureId.bykc,
      FeatureId.classroom,
      FeatureId.libbook,
      FeatureId.cgyy,
      FeatureId.evaluation,
    ]) {
      expect(
        shell().snapshots[feature]!.status,
        FeatureLoadStatus.idle,
        reason: '首页不得预载未访问的领域默认页',
      );
    }
    for (final source in HomeSupplement.values) {
      final before = shell().snapshots;
      FeatureResult? result;
      final pending = shell().onLoadHomeSupplement!(source, false).then(
        (value) => result = value,
      );
      await waitFor(() => result != null, '首页补充来源未在限定时间完成');
      await pending;
      debugPrint(
        '首页只读 supplement=${source.name} status=${result!.error != null
            ? 'failure'
            : result!.isEmpty
            ? 'empty'
            : 'success'} route=${result!.resolvedRoute?.name} count=${result!.details.length} error=${result!.error?.code.name}',
      );
      expect(result!.error == null, isTrue);
      expect(result!.resolvedRoute?.name, route);
      for (final feature in [
        FeatureId.schedule,
        FeatureId.bykc,
        FeatureId.cgyy,
      ]) {
        expect(
          identical(shell().snapshots[feature], before[feature]),
          isTrue,
          reason: '补充来源不能覆盖当前领域查询',
        );
      }
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TextField).evaluate().isEmpty, isTrue);
    final icon = find.byTooltip(route == 'direct' ? '实际路线：直连' : '实际路线：WebVPN');
    await waitFor(() => icon.evaluate().isNotEmpty, '首页聚合实际路线未更新');
    await tester.tap(icon);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('连接路线').evaluate().isNotEmpty, isTrue);
    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pump(const Duration(milliseconds: 300));
    debugPrint('生产首页八项默认与补充只读来源完成，businessWrites=0');
  });
}
