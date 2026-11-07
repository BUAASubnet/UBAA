import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/recovery.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('地点偏好挂起时首页已显示并开始恢复', (tester) async {
    final accounts = await widgetAccounts(tester);
    final backend = FakeRecoveryBackend()..gate = Completer();
    final preferences = _Preferences();
    await tester.pumpWidget(
      UbaaAppHost(
        backend: backend,
        localAccountStore: accounts,
        preferenceValues: preferences,
      ),
    );
    await accounts.settle(tester);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(UbaaMainShell), findsOneWidget);
    expect(backend.authCalls, 1);
    preferences.gate.complete(null);
    backend.gate!.completeError(StateError('合成网络不可用'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
  });
}

class _Preferences implements PreferenceValues {
  final gate = Completer<String?>();
  @override
  Future<String?> read(String key) =>
      key.contains('.places.') ? gate.future : Future.value(null);
  @override
  Future<void> write(String key, String value) async {}
  @override
  Future<void> remove(String key) async {}
}
