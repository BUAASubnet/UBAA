import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'materials.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 在 tester.runAsync 中等待真实文件 I/O 引起的界面状态变化。
/// pumpAndSettle 只等待帧，后台文件请求尚未结束时可能提前返回。
Future<void> pumpRecoveryUntil(
  WidgetTester tester,
  bool Function() completed,
) async {
  final watch = Stopwatch()..start();
  while (!completed()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      throw TestFailure('真实异步恢复未到达预期状态');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

Future<LocalAccountStore> savedAccounts() async {
  final materials = syntheticMaterials(MemoryMaterials());
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

/// 在真实 Zone 创建账号操作，保留 Widget 测试的虚拟业务时钟。
/// 每次调用仍委托 SecureLocalAccountStore，覆盖真实账号索引与文件锁。
Future<WidgetAccounts> widgetAccounts(
  WidgetTester tester, {
  String username = 'fixture-user',
}) async {
  final accounts = (await tester.runAsync(() async {
    final materials = syntheticMaterials(MemoryMaterials());
    await materials.probe();
    final delegate = SecureLocalAccountStore(materials);
    await delegate.retain(username, retainSession: true);
    return WidgetAccounts._(delegate, Zone.current);
  }))!;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await accounts.settle(tester);
  });
  return accounts;
}

class WidgetAccounts implements LocalAccountStore {
  WidgetAccounts._(this._delegate, this._ioZone);
  final SecureLocalAccountStore _delegate;
  final Zone _ioZone;
  final _pending = <Future<void>>{};

  Future<T> _run<T>(Future<T> Function() action) => _ioZone.run(() {
    final operation = Future<T>.sync(action);
    late final Future<void> tracked;
    tracked = operation.then<void>(
      (_) => _pending.remove(tracked),
      onError: (Object error, StackTrace stack) {
        _pending.remove(tracked);
      },
    );
    _pending.add(tracked);
    return operation;
  });

  /// 仅排空已发起的账号 I/O 与其界面续接，不推进虚拟业务时间。
  Future<void> settle(WidgetTester tester) async {
    do {
      await tester.runAsync(() => Future.wait(_pending.toList()));
      await tester.pump();
    } while (_pending.isNotEmpty);
  }

  @override
  Future<LocalAccountState?> read() => _run(_delegate.read);
  @override
  Future<LocalAccountState> retain(
    String username, {
    required bool retainSession,
  }) => _run(() => _delegate.retain(username, retainSession: retainSession));
  @override
  Future<Uint8List> cacheKey(LocalAccount account) =>
      _run(() => _delegate.cacheKey(account));
  @override
  Future<void> signOut() => _run(_delegate.signOut);
  @override
  Future<void> removeAccount(String accountId) =>
      _run(() => _delegate.removeAccount(accountId));
}
