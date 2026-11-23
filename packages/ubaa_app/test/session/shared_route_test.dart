import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/bridge/auth/session.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import 'package:ubaa_app/src/contracts/routing.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../../ubaa_platform/test/support/test_tmp.dart';
import '../runtime/shared_recovery_probe.dart' show openAccounts;
import '../support/bridge/recording_client.dart';

class _Client extends FixtureCharacterizationBridgeClient {
  int releases = 0;
  @override
  Future<void> releaseSharedAccountForLogin() async {
    releases++;
  }
}

void main() {
  test('普通路线准备保留固定账号归属', () async {
    final root = createTestTempDirectory('ubaa_app_shared_route');
    final client = _Client();
    try {
      final accounts = await openAccounts(root);
      await accounts.retain('synthetic-route', retainSession: true);
      final binding = await accounts.bindSnapshot((await accounts.capture())!);
      final context = BridgeContext(client)..sharedAccount = binding;
      await bridgePrepareLogin(
        context,
        RoutePolicy.direct,
        (policy) async =>
            BackendRouteSettings(defaultPolicy: policy, activeRoutes: const []),
      );
      expect(client.releases, 0);
      await binding.validate();
      expect(client.calls, ['client.prepareLogin']);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
