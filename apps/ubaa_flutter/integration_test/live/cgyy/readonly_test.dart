import '../../navigation.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_flutter/main.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

/// 正常生产启动与真实只读分页；禁止截图、业务写入及输出个人字段。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('生产研讨室零基分页与详情只读复验', (tester) async {
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
    final login = find.byType(UbaaLoginView);
    if (login.evaluate().isNotEmpty) {
      debugPrint(
        '只读启动 login=true error=${tester.widget<UbaaLoginView>(login).error?.code.name}',
      );
    }
    expect(
      find.byType(UbaaMainShell).evaluate().isNotEmpty,
      isTrue,
      reason: '生产会话未恢复到主界面，未执行任何业务查询',
    );
    FeatureSnapshot snapshot() => tester
        .widget<UbaaMainShell>(find.byType(UbaaMainShell))
        .snapshots[FeatureId.cgyy]!;
    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 150));
    }

    Future<void> loaded(
      FeatureQueryView view, {
      int? page,
      int? size,
      int? orderId,
      int? previousRevision,
    }) async {
      await waitFor(() {
        final value = snapshot();
        final query = value.readContext?.query;
        return query?.view == view &&
            (page == null || query?.page == page) &&
            (size == null || query?.size == size) &&
            (orderId == null || query?.orderId == orderId) &&
            (previousRevision == null ||
                value.readContext?.requestRevision != previousRevision) &&
            value.status != FeatureLoadStatus.idle &&
            value.status != FeatureLoadStatus.loading;
      }, '只读查询未在限定时间完成');
      final value = snapshot();
      debugPrint(
        '只读分页 view=${view.name} status=${value.status.name} '
        'route=${value.resolvedRoute?.name} page=${value.readContext?.query?.page} '
        'displayPage=${value.pagination?.page} size=${value.pagination?.size} '
        'count=${value.details.length} total=${value.pagination?.total} '
        'error=${value.error?.code.name}',
      );
      expect(
        value.status == FeatureLoadStatus.success ||
            value.status == FeatureLoadStatus.empty,
        isTrue,
        reason: '只读结果未成功，固定状态见安全日志',
      );
      expect(value.resolvedRoute?.name, route);
      await tester.pump(const Duration(milliseconds: 250));
    }

    await tap(uiDestinationFinder(tester, UiDestination.campus));
    await tap(find.widgetWithText(Card, FeatureId.cgyy.title));
    await tap(find.widgetWithText(Card, '我的预约'));
    await loaded(FeatureQueryView.cgyyOrders, page: 0);
    expect(snapshot().pagination?.page, 1);
    // 本轮账号由安全Core-live已确认首批有记录；只断言数量，不输出记录。
    expect(snapshot().details.isNotEmpty, isTrue);

    final more = snapshot().pagination;
    if (more != null &&
        (more.hasMore ?? (more.page < more.effectiveTotalPages))) {
      final revision = snapshot().readContext?.requestRevision;
      final list = find.byType(ListView).last;
      for (
        var i = 0;
        i < 80 && snapshot().readContext?.requestRevision == revision;
        i++
      ) {
        await tester.drag(list, const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 500));
      }
      await loaded(
        FeatureQueryView.cgyyOrders,
        page: more.page,
        size: more.size,
        previousRevision: revision,
      );
    }
    await tap(find.byTooltip('刷新当前查询'));
    await loaded(FeatureQueryView.cgyyOrders, page: 0);
    final order =
        snapshot().details.first.presentation as CgyyOrderPresentation;
    await tap(find.widgetWithText(TextButton, '查看详情').first);
    await loaded(FeatureQueryView.cgyyOrderDetail, orderId: order.id);
    expect(snapshot().details.length, 1);
    expect(find.byType(TextField), findsNothing);
    debugPrint('生产研讨室分页与详情只读操作完成，businessWrites=0');
  });
}
