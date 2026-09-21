import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('原生 Bridge v10 缓存句柄可重开且退出栅栏跨句柄生效', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('本地缓存合成验证'))),
    );
    await RustLib.init();
    final directory = await Directory.systemTemp.createTemp(
      'ubaa-cache-probe-',
    );
    final key = Uint8List.fromList(List.filled(32, 7));
    BridgeOfflineCache? first;
    BridgeOfflineCache? second;
    BridgeClient? client;
    try {
      client = BridgeClient.open(configDir: directory.path);
      expect(client.contractVersion(), 10);
      first = await BridgeOfflineCache.open(
        configDir: directory.path,
        accountId: '0123456789abcdef0123456789abcdef',
        expectedIdentity: 'synthetic',
        key: key,
      );
      expect(await first.readToday(route: BridgeConnectionMode.direct), isNull);
      second = await BridgeOfflineCache.open(
        configDir: directory.path,
        accountId: '0123456789abcdef0123456789abcdef',
        expectedIdentity: 'synthetic',
        key: key,
      );
      await first.deactivate();
      await expectLater(
        second.readToday(route: BridgeConnectionMode.direct),
        throwsA(
          isA<BridgeError>().having(
            (error) => error.code,
            '退出栅栏',
            BridgeErrorCode.authenticationRequired,
          ),
        ),
      );
      await second.activate();
      expect(await first.readToday(route: BridgeConnectionMode.webVpn), isNull);
      await second.clear();
    } finally {
      key.fillRange(0, key.length, 0);
      await client?.dispose();
      first?.dispose();
      second?.dispose();
      await directory.delete(recursive: true);
    }
  });
}
