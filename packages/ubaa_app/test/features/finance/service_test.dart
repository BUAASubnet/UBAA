import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import 'package:ubaa_app/src/bridge/finance/service.dart';
import 'package:ubaa_app/src/contracts/recovery.dart';
import 'package:ubaa_app/src/controller/features/finance/service.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('查询先恢复所需会话，精确保留金额与缺失项', () async {
    final client = _Client();
    final service = BridgeFinanceService(BridgeContext(client), () async {
      client.calls.add('recover');
      return const RecoveredRouteSession(
        route: ConnectionMode.direct,
        profile: UserSummary(username: 'synthetic'),
      );
    });
    expect(await service.cached(), isNull);
    final value = await service.refresh();
    expect(client.calls, ['recover', 'read']);
    expect(value.entries.single.amountCents, 1234);
    expect(value.entries.single.paidCents, 0);
    expect(value.entries.single.taxCents, isNull);
    expect(value.fromCache, isFalse);
    expect(value.savedForOffline, isFalse);
    expect(() => value.entries.clear(), throwsUnsupportedError);
  });
  test('账号变化拒绝迟到结果和旧服务继续查询', () async {
    final gate = Completer<FinanceSnapshot>();
    var current = true;
    final delegate = _Service(gate);
    final service = GuardedFinanceService(delegate, () => current);
    final pending = service.refresh();
    current = false;
    final check = expectLater(pending, throwsA(isA<UiError>()));
    gate.complete(
      FinanceSnapshot(
        entries: [],
        total: 0,
        route: ConnectionMode.direct,
        fetchedAt: DateTime.utc(2026),
        fromCache: false,
        savedForOffline: false,
      ),
    );
    await check;
    await expectLater(service.refresh(), throwsA(isA<UiError>()));
    expect(delegate.calls, 1);
  });
}

class _Service implements FinanceService {
  _Service(this.gate);
  final Completer<FinanceSnapshot> gate;
  int calls = 0;
  @override
  Future<FinanceSnapshot> refresh() {
    calls++;
    return gate.future;
  }

  @override
  Future<FinanceSnapshot?> cached() async => null;
}

class _Client implements BridgeClient {
  final calls = <String>[];
  @override
  Future<BridgeFinanceResult> financeIncomes() async {
    calls.add('read');
    return const BridgeFinanceResult(
      route: BridgeRouteDecision(
        policy: BridgeRoutePolicy.direct,
        resolvedRoute: BridgeConnectionMode.direct,
        network: BridgeNetworkState.campus,
        initialRoute: BridgeConnectionMode.direct,
        usedFallback: false,
      ),
      data: BridgeFinanceIncomes(
        total: 1,
        entries: [
          BridgeFinanceIncome(id: 'fixture', amountCents: 1234, paidCents: 0),
        ],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
