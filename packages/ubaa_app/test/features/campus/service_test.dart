import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_app/src/controller/features/campus/service.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('无缓存时调用三个只读接口，保留金额、单位、零值与缺失项', () async {
    final client = _Client();
    final service = BridgeBackend(client).campusAccount;
    expect((await service.cached()).isEmpty, isTrue);
    expect((await service.identity()).department, '合成学院');
    final metrics = await service.metrics();
    expect(
      (metrics.cardBalance as CampusMetricValue<CampusAmount>).value.value,
      '10.659999999999998',
    );
    expect((metrics.unreadMail as CampusMetricValue<int>).value, 0);
    expect(metrics.borrowedBooks, isNull);
    expect(metrics.networkBalance, isA<CampusMetricFailure<CampusAmount>>());
    final network = await service.networkUsage();
    expect(network.remainingExcludesPackages, isTrue);
    expect(
      network.fetchedAt,
      DateTime.fromMillisecondsSinceEpoch(100000, isUtc: true),
    );
    expect(client.calls, ['profile', 'metrics', 'network']);
  });
  test('代次失效拒绝迟到结果与后续请求', () async {
    final client = _Client()..gate = Completer<BridgePortalProfileResult>();
    var current = true;
    final service = GuardedCampusAccountService(
      BridgeBackend(client).campusAccount,
      () => current,
    );
    final pending = service.identity();
    await Future<void>.delayed(Duration.zero);
    current = false;
    final expectation = expectLater(
      pending,
      throwsA(
        isA<UiError>().having(
          (e) => e.code,
          '错误码',
          UbaaErrorCode.operationConflict,
        ),
      ),
    );
    client.gate!.complete(_profile);
    await expectation;
    await expectLater(service.networkUsage(), throwsA(isA<UiError>()));
    expect((await service.cached()).isEmpty, isTrue);
    expect(client.calls, ['profile']);
  });
}

const _route = BridgeRouteDecision(
  policy: BridgeRoutePolicy.direct,
  resolvedRoute: BridgeConnectionMode.direct,
  network: BridgeNetworkState.campus,
  initialRoute: BridgeConnectionMode.direct,
  usedFallback: false,
);
const _profile = BridgePortalProfileResult(
  data: BridgePortalProfile(
    identity: '本科生',
    department: '合成学院',
    fetchedAt: 100,
  ),
  route: _route,
);

class _Client implements BridgeClient {
  final calls = <String>[];
  Completer<BridgePortalProfileResult>? gate;
  @override
  int contractVersion() => 43;
  @override
  Future<BridgePortalProfileResult> portalProfile() {
    calls.add('profile');
    return gate?.future ?? Future.value(_profile);
  }

  @override
  Future<BridgeCampusMetricsResult> campusMetrics() async {
    calls.add('metrics');
    return const BridgeCampusMetricsResult(
      route: _route,
      data: BridgeCampusMetrics(
        cardBalance: BridgeCampusAmountMetric(
          value: BridgeCampusAmount(value: '10.659999999999998', unit: '元'),
          fetchedAt: 100,
        ),
        networkBalance: BridgeCampusAmountMetric(
          failure: BridgeCampusMetricFailure(
            code: BridgeErrorCode.networkError,
            message: '不展示上游原文',
          ),
          fetchedAt: 100,
        ),
        unreadMail: BridgeCampusCountMetric(value: 0, fetchedAt: 100),
        borrowedBooks: BridgeCampusCountMetric(fetchedAt: 0),
        cloudStorageRemaining: BridgeCampusAmountMetric(fetchedAt: 0),
      ),
    );
  }

  @override
  Future<BridgeNetworkUsageResult> networkUsage() async {
    calls.add('network');
    return const BridgeNetworkUsageResult(
      route: _route,
      data: BridgeNetworkUsage(
        products: [],
        remainingExcludesPackages: true,
        fetchedAt: 100,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
