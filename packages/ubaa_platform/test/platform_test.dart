import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('内存凭据保险箱支持单账号覆盖和清除', () async {
    final vault = MemoryCredentialVault();
    expect(await vault.read(), isNull);
    await vault.write(const StoredCredential(username: 'u1', password: 'p1'));
    expect((await vault.read())?.username, 'u1');
    await vault.write(const StoredCredential(username: 'u2', password: 'p2'));
    expect((await vault.read())?.username, 'u2');
    await vault.clear();
    expect(await vault.read(), isNull);
  });

  test('遥测关闭时不缓存事件，开启后仅缓存白名单字段', () async {
    final telemetry = InMemoryTelemetryClient();
    await telemetry.recordAppOpen();
    expect(telemetry.events, isEmpty);
    await telemetry.setEnabled(true);
    await telemetry.recordFeatureUsed(
      FeatureId.schedule,
      outcome: TelemetryOutcome.success,
      latency: const Duration(milliseconds: 100),
    );
    expect(telemetry.events.single.properties['feature'], 'schedule');
    expect(telemetry.events.single.properties.containsKey('password'), isFalse);
    await telemetry.setEnabled(false);
    expect(telemetry.events, isEmpty);
  });
}
