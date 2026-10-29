import 'dart:async';

import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

Future<LocalAccountStore> savedAccounts() async {
  final materials = SecureMaterialStore(transport: MemoryMaterials());
  await materials.probe();
  final accounts = SecureLocalAccountStore(materials);
  await accounts.retain('fixture-user', retainSession: true);
  return accounts;
}

class MemoryMaterials implements SecureMaterialTransport {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class FakeRecoveryBackend implements UbaaBackend {
  Completer<AuthStatus>? gate;
  Completer<void>? loginGate;
  BackendException? authError;
  BackendException? loginError;
  bool signedIn = true;
  String username = 'fixture-user';
  int authCalls = 0;
  int loginCalls = 0;
  int readCalls = 0;
  @override
  Future<AuthStatus> authStatus() async {
    authCalls++;
    if (authError case final error?) throw error;
    if (gate case final pending?) return pending.future;
    return signedIn ? AuthStatus.signedIn : AuthStatus.signedOut;
  }

  @override
  Future<UserSummary?> userInfo() async => UserSummary(username: username);
  @override
  Future<void> prepareLogin(RoutePolicy policy) async {}
  @override
  Future<void> login(LoginInput input) async {
    loginCalls++;
    if (loginError case final error?) throw error;
    if (loginGate case final pending?) await pending.future;
    signedIn = true;
  }

  @override
  Future<void> logout() async {
    signedIn = false;
  }

  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    readCalls++;
    return const FeatureResult.empty();
  }
}
