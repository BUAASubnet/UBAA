import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/ubaa_ui.dart';
import 'package:ubaa_flutter/main.dart';

/// 显式生产只读入口：Core安全登录先在私有隔离目录建立会话。
/// 不读取凭据、不截取个人数据、不调用任何业务写入回调。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产App恢复真实会话并巡检十二领域只读页面', (tester) async {
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY')) {
      throw StateError('必须显式启用生产只读验收');
    }
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    if (config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-')) {
      throw StateError('必须使用本轮私有隔离目录');
    }
    Widget? application;
    await bootstrapUbaaFlutterApp(runApplication: (app) => application = app);
    await tester.pumpWidget(application!);

    Future<bool> waitFor(bool Function() ready) async {
      for (var step = 0; step < 180; step++) {
        if (ready()) return true;
        await tester.pump(const Duration(milliseconds: 500));
      }
      return ready();
    }

    final restored = await waitFor(
      () => find.byType(UbaaMainShell).evaluate().isNotEmpty,
    );
    expect(restored, isTrue, reason: '生产会话恢复未在90秒内完成');
    await tester.pumpAndSettle();
    final records = <Map<String, Object?>>[];
    for (final feature in FeatureId.values) {
      final loaded = await waitFor(() {
        final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
        final status = shell.snapshots[feature]?.status;
        return status != FeatureLoadStatus.loading &&
            status != FeatureLoadStatus.idle;
      });
      final index = ordinaryFeatureIds.contains(feature) ? 1 : 2;
      final rail = find.byType(NavigationRail);
      if (rail.evaluate().isNotEmpty) {
        final current = tester.widget<NavigationRail>(rail).selectedIndex;
        if (current != index) {
          await tester.tap(
            find.descendant(
              of: rail,
              matching: find.byIcon(
                index == 1 ? Icons.apps_outlined : Icons.auto_awesome_outlined,
              ),
            ),
          );
        }
      } else {
        await tester.tap(find.byType(NavigationDestination).at(index));
      }
      await tester.pumpAndSettle();
      final card = find.widgetWithText(Card, feature.title);
      if (card.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          card,
          200,
          scrollable: find.descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          ),
        );
      }
      await tester.ensureVisible(card);
      await tester.pumpAndSettle();
      await tester.tap(card);
      await tester.pumpAndSettle();
      var snapshot = tester
          .widget<UbaaMainShell>(find.byType(UbaaMainShell))
          .snapshots[feature]!;
      final initialStatus = snapshot.status.name;
      final initialError = snapshot.error?.code.name;
      var retried = false;
      if (const bool.fromEnvironment('UBAA_LIVE_RETRY_FAILED') &&
          snapshot.status == FeatureLoadStatus.failure) {
        retried = true;
        final revision = snapshot.readContext?.requestRevision;
        await tester.tap(find.byTooltip('刷新当前查询'));
        await waitFor(() {
          final current = tester
              .widget<UbaaMainShell>(find.byType(UbaaMainShell))
              .snapshots[feature]!;
          return current.readContext?.requestRevision != revision &&
              current.status != FeatureLoadStatus.loading;
        });
        await tester.pumpAndSettle();
        snapshot = tester
            .widget<UbaaMainShell>(find.byType(UbaaMainShell))
            .snapshots[feature]!;
      }
      final visible =
          find.widgetWithText(AppBar, feature.title).evaluate().length == 1;
      final noQueryBlock = find.byType(TextField).evaluate().isEmpty;
      records.add({
        'feature': feature.wireName,
        'initialStatus': initialStatus,
        'initialError': initialError,
        'explicitRefresh': retried,
        'loaded': loaded,
        'visible': visible,
        'queryHidden': noQueryBlock,
        'status': snapshot.status.name,
        'actualRoute': snapshot.resolvedRoute?.name,
        'error': snapshot.error?.code.name,
        'count': snapshot.details.length,
      });
      expect(visible && noQueryBlock, isTrue, reason: '领域页标题或查询收纳未符合要求');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
    }
    binding.reportData = {
      'backend': 'production-frb',
      'credentialEntry': 'existing-core-live-stdin-private-session',
      'scope': 'native-macos-session-restore-and-default-readonly-pages',
      'source': const String.fromEnvironment('UBAA_UI_SOURCE_SHA'),
      'records': records,
      'businessWrites': 0,
    };
    // 只输出固定字段与安全计数，不打印Widget、DTO、用户或错误正文。
    for (final record in records) {
      debugPrint(
        '只读验收 feature=${record['feature']} status=${record['status']} route=${record['actualRoute']} error=${record['error']} count=${record['count']} visible=${record['visible']} queryHidden=${record['queryHidden']} initialStatus=${record['initialStatus']} initialError=${record['initialError']} explicitRefresh=${record['explicitRefresh']}',
      );
    }
    const expectedRoute = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    expect(
      expectedRoute == 'direct' || expectedRoute == 'webvpn',
      isTrue,
      reason: '必须指定预期真实路线',
    );
    expect(
      records
          .where((r) => r['status'] == 'success' || r['status'] == 'empty')
          .every((r) => r['actualRoute'] == expectedRoute),
      isTrue,
      reason: '实际读取路线与本轮固定路线不一致',
    );
    expect(
      records.every((r) => r['loaded'] == true),
      isTrue,
      reason: '部分只读请求未完成',
    );
    expect(
      records.every((r) => r['status'] == 'success' || r['status'] == 'empty'),
      isTrue,
      reason: '存在未通过的生产只读页面，见安全状态记录',
    );
  });
}
