import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/bridge/bridge_backend.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_bindings/src/rust/frb_generated.dart' show RustLibApi;
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/materials.dart';
import 'package:ubaa_test_support/recovery.dart' show MemoryMaterials;

import '../../support/bridge/fixtures.dart' show currentBridgeContractVersion;

void main() {
  final api = _Api();
  setUpAll(() => RustLib.initMock(api: api));

  for (final retainSession in [false, true]) {
    test('生产 BridgeBackend 绑定传递保留标记=$retainSession', () async {
      final materials = syntheticMaterials(MemoryMaterials());
      await materials.probe();
      final accounts = SecureLocalAccountStore(materials);
      await accounts.retain('fixture-user', retainSession: retainSession);
      final binding = await accounts.bindSnapshot(
        (await accounts.capture())!,
        requireRestore: false,
      );
      final client = _Client();
      final backend = BridgeBackend(client);
      addTearDown(backend.dispose);

      api.retainSessions.clear();
      await backend.bindSharedAccount(binding);

      expect(api.retainSessions, [retainSession]);
      expect(client.expectedUsername, 'fixture-user');
    });
  }
}

class _Api implements RustLibApi {
  final retainSessions = <bool>[];

  @override
  Future<BridgeSharedAccount> crateApiSharedAccountBridgeSharedAccountCapture({
    required String directory,
    required BigInt generation,
    required bool retainSession,
  }) async {
    retainSessions.add(retainSession);
    return _NativeSharedAccount();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NativeSharedAccount implements BridgeSharedAccount {
  bool disposed = false;
  @override
  void dispose() => disposed = true;
  @override
  bool get isDisposed => disposed;
}

class _Client implements BridgeClient {
  String? expectedUsername;
  @override
  int contractVersion() => currentBridgeContractVersion;

  @override
  Future<void> bindSharedAccount({
    required BridgeSharedAccount scope,
    String? expectedDiagnosticsUsername,
  }) async {
    expectedUsername = expectedDiagnosticsUsername;
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
