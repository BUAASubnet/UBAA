import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/app/account/campus_recharge.dart';

const _merchant = 'https://cashier.cc-pay.cn/cashier?id=synthetic-order';

enum _FirstOpen { success, failure, exception }

void main() {
  for (final firstOpen in _FirstOpen.values) {
    testWidgets('确认充值后打开原商户收银台（${firstOpen.name}）', (tester) async {
      final service = _RechargeService();
      final opened = <Uri>[];
      final rejected = <Object>[];
      await tester.pumpWidget(
        MaterialApp(
          home: CampusRechargePage(
            service: service,
            supportsCashier: () async {
              expect(service.preflightCalls, 0);
              return true;
            },
            openCashier: (url) async {
              opened.add(url);
              if (opened.length != 1) return true;
              return switch (firstOpen) {
                _FirstOpen.success => true,
                _FirstOpen.failure => false,
                _FirstOpen.exception => throw StateError('failed for $url'),
              };
            },
            onRejected: rejected.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final submit = find.byKey(const ValueKey('campus-recharge-submit'));
      final submitAction = tester.widget<FilledButton>(submit).onPressed!;
      expect(service.preflightCalls, 1);
      expect(find.text('支付渠道：支付宝'), findsOneWidget);
      expect(find.text('支付方式'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('campus-recharge-amount')),
        '12.34',
      );
      submitAction();
      submitAction();
      await tester.pumpAndSettle();
      expect(find.text('确认充值'), findsOneWidget);
      expect(find.textContaining('12.34 元'), findsOneWidget);
      expect(find.textContaining('支付宝。请在支付宝内核对订单并确认付款。'), findsOneWidget);
      expect(service.requests, isEmpty);
      expect(opened, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(service.requests, isEmpty);
      expect(opened, isEmpty);

      await tester.tap(submit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认'));
      await tester.pumpAndSettle();
      expect(service.requests, [(idserial: '123456', amountFen: '1234')]);
      expect(opened, isEmpty);
      submitAction();
      service.orderReady.complete();
      await tester.pumpAndSettle();
      submitAction();
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(service.requests, [(idserial: '123456', amountFen: '1234')]);
      expect(find.text('synthetic-order'), findsOneWidget);
      expect(find.textContaining('下单失败'), findsNothing);
      expect(rejected, isEmpty);
      expect(find.text(_merchant), findsNothing);
      expect(find.textContaining('复制'), findsNothing);

      final merchant = Uri.parse(_merchant);
      expect(opened, [merchant]);
      final failed = find.text('未能在应用内打开航财通收银台。');
      if (firstOpen == _FirstOpen.success) {
        expect(failed, findsNothing);
      } else {
        expect(failed, findsOneWidget);
        final retry = find.widgetWithText(OutlinedButton, '重新打开航财通收银台');
        final retryAction = tester.widget<OutlinedButton>(retry).onPressed!;
        retryAction();
        retryAction();
        await tester.pumpAndSettle();
        expect(opened, [merchant, merchant]);
        expect(service.requests, hasLength(1));
        expect(find.text('synthetic-order'), findsOneWidget);
        expect(failed, findsNothing);
        expect(rejected, isEmpty);
      }
    });
  }

  testWidgets('不支持应用内收银台时不查询校园卡或下单', (tester) async {
    final service = _RechargeService();
    final supported = Completer<bool>();
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CampusRechargePage(
          service: service,
          supportsCashier: () => supported.future,
          openCashier: (url) async {
            opened.add(url);
            return true;
          },
        ),
      ),
    );
    expect(service.preflightCalls, 0);

    supported.complete(false);
    await tester.pumpAndSettle();

    expect(find.textContaining('此设备不支持应用内收银台'), findsOneWidget);
    expect(find.textContaining('未创建订单'), findsOneWidget);
    expect(find.byKey(const ValueKey('campus-recharge-submit')), findsNothing);
    expect(service.preflightCalls, 0);
    expect(service.requests, isEmpty);
    expect(opened, isEmpty);
  });
}

class _RechargeService implements CampusRechargeService {
  int preflightCalls = 0;
  final orderReady = Completer<void>();
  final requests = <({String idserial, String amountFen})>[];

  @override
  Future<CampusRechargePreflight> preflight() async {
    preflightCalls++;
    return CampusRechargePreflight(
      idserial: '123456',
      balance: '2.50',
      fetchedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<CampusRechargeOrder> createOrder({
    required String idserial,
    required String amountFen,
  }) async {
    requests.add((idserial: idserial, amountFen: amountFen));
    await orderReady.future;
    return CampusRechargeOrder(
      orderno: 'synthetic-order',
      cashierUrl: _merchant,
      amountFen: amountFen,
      fetchedAt: DateTime.utc(2026),
    );
  }
}
