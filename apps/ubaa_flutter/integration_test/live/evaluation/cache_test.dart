import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

/// 原生生产 Bridge/Adapter 的评教只读验证，不进入学校写前或提交步骤。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实评教只读计划按批返回且可独立重开缓存', (tester) async {
    final config = Platform.environment['UBAA_CONFIG_DIR'];
    const route = String.fromEnvironment('UBAA_EXPECTED_ROUTE');
    if (!const bool.fromEnvironment('UBAA_LIVE_READONLY') ||
        config == null ||
        !Directory(config).isAbsolute ||
        !config.contains('UBAA-ui-readonly-offline-') ||
        (route != 'direct' && route != 'webvpn')) {
      throw StateError('必须显式指定本轮私有目录及只读路线');
    }
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('评教显示只读验收'))),
    );
    await RustLib.init();
    final random = Random.secure();
    final key = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final alias = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _ReadonlyBackend? backend;
    try {
      backend = _ReadonlyBackend(
        await BridgeClient.open(configDir: config),
        config,
      );
      final session = await backend.recoverRequiredSession(
        FeatureId.evaluation,
      );
      expect(session.route.name == route, isTrue);
      final account = LocalAccount(
        id: alias,
        username: session.profile.username,
      );
      await backend.openOfflineAccount(account, key);
      final elapsed = Stopwatch()..start();
      final task = (await backend.beginAccountFeatureRead(
        FeatureId.evaluation,
        const FeatureQuery(),
        account,
      ))!;
      var batches = 0;
      late FeatureResult last;
      while (true) {
        final batch = await task.next();
        batches++;
        if (batches == 1) {
          await backend.recoverRequiredSession(FeatureId.schedule);
        }
        if (batch.finished) {
          last = batch.result;
          break;
        }
      }
      task.cancel();
      debugPrint(
        '评教只读阶段 route=$route batches=$batches complete=${last.evidence?.complete} error=${last.error?.code.name} retryable=${last.error?.retryable} businessWrites=${backend.commits}',
      );
      expect(batches >= 2, isTrue);
      expect(last.evidence?.complete, isTrue);
      expect(last.evidence?.savedForOffline, isTrue);
      expect(backend.commits, 0);
      final onlineMs = elapsed.elapsedMilliseconds;
      final count = last.details.length;
      await backend.dispose();
      backend = _ReadonlyBackend(
        await BridgeClient.open(configDir: config),
        config,
      );
      await backend.openOfflineAccount(account, key);
      final cached = await backend.readCachedQuery(
        FeatureId.evaluation,
        const FeatureQuery(),
        route == 'direct' ? RoutePolicy.direct : RoutePolicy.webvpn,
      );
      expect(cached.projection != null, isTrue);
      expect(cached.projection!.complete, isTrue);
      expect(cached.projection!.details.length, count);
      expect(
        cached.projection!.details.expand((row) => row.actions).isEmpty,
        isTrue,
      );
      expect(backend.recoveries, 0);
      expect(backend.commits, 0);
      debugPrint(
        '评教只读 route=$route batches=$batches courses=$count online_ms=$onlineMs cacheReopen=true cacheComplete=true businessWrites=0 processCold=false',
      );
    } finally {
      key.fillRange(0, key.length, 0);
      await backend?.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class _ReadonlyBackend extends BridgeBackend {
  _ReadonlyBackend(super.client, String config)
    : super(configDirectory: config);
  int commits = 0, recoveries = 0;
  @override
  Future<RecoveredRouteSession> recoverRequiredSession(FeatureId feature) {
    recoveries++;
    return super.recoverRequiredSession(feature);
  }

  @override
  Future<WriteCommitResult> commitWrite(String intentId) async {
    commits++;
    throw StateError('真实只读验收禁止业务提交');
  }

  @override
  Future<WriteCommitResult> commitWriteWithCache(
    String intentId, {
    required String accountId,
  }) => commitWrite(intentId);
}
