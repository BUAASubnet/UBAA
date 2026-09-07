import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'bridge_fixture.dart';

void registerAccountPartialFixtureContract() {
  test('真实适配器消费合成partial结果只保留直连且未实现业务明确失败', () async {
    final client = AccountPartialBridgeClient();
    final backend = BridgeBackend(client);
    expect(await backend.authStatus(), AuthStatus.signedOut);
    await backend.login(
      const LoginInput(
        username: 'partial-fixture',
        password: 'synthetic-password',
      ),
    );
    expect(
      AccountPartialBridgeClient.outcome.readiness,
      BridgeLoginReadiness.partial,
    );
    expect(AccountPartialBridgeClient.outcome.routes.map((r) => r.state), [
      BridgeRouteLoginState.ready,
      BridgeRouteLoginState.failed,
    ]);
    expect((await backend.routeSettings()).activeRoutes, [
      ConnectionMode.direct,
    ]);
    expect(await backend.authStatus(), AuthStatus.signedIn);
    expect((await backend.userInfo())?.email, 'partial@example.invalid');
    for (final feature in FeatureId.values) {
      await expectLater(
        backend.loadFeature(feature),
        throwsA(isA<UnsupportedError>()),
      );
    }
    expect(client.unsupportedReads, greaterThanOrEqualTo(12));
  });
}
