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

/// 原生生产 Bridge/Adapter 的真实详情只读验证；不计作完整 UI 或冷启动验收。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('SPOC 真实只读详情按页推进并可独立重开缓存', (tester) async {
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
      const MaterialApp(home: Scaffold(body: Text('SPOC 详情只读验收'))),
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
      final session = await backend.recoverRequiredSession(FeatureId.spoc);
      expect(session.route.name == route, isTrue);
      final account = LocalAccount(
        id: alias,
        username: session.profile.username,
      );
      await backend.openOfflineAccount(account, key);
      final index = (await backend.beginAccountFeatureRead(
        FeatureId.spoc,
        null,
        account,
      ))!;
      late FeatureResult listing;
      while (true) {
        final batch = await index.next();
        if (batch.finished) {
          listing = batch.result;
          break;
        }
      }
      index.cancel();
      expect(listing.details.isNotEmpty, isTrue, reason: '没有可验证的真实目标');
      final id =
          (listing.details.first.presentation as SpocAssignmentPresentation)
              .assignmentId;
      final query = FeatureQuery(
        view: FeatureQueryView.spocDetail,
        assignmentId: id,
      );
      final elapsed = Stopwatch()..start();
      final task = (await backend.beginAccountFeatureRead(
        FeatureId.spoc,
        query,
        account,
      ))!;
      var prefixes = 0;
      late FeatureResult detail;
      while (true) {
        final batch = await task.next();
        if (!batch.publish) {
          prefixes++;
          if (prefixes == 1) {
            await backend.recoverRequiredSession(FeatureId.schedule);
          }
        }
        if (batch.finished) {
          detail = batch.result;
          break;
        }
      }
      task.cancel();
      expect(prefixes >= 3, isTrue);
      expect(detail.details.length, 1);
      expect(
        (detail.details.single.presentation as SpocAssignmentPresentation)
                .assignmentId ==
            id,
        isTrue,
      );
      expect(detail.evidence?.complete, isTrue);
      expect(detail.evidence?.savedForOffline, isTrue);
      expect(detail.details.single.actions.isEmpty, isTrue);
      final detailMs = elapsed.elapsedMilliseconds;
      expect(backend.commits, 0);
      await backend.dispose();
      backend = _ReadonlyBackend(
        await BridgeClient.open(configDir: config),
        config,
      );
      await backend.openOfflineAccount(account, key);
      final cached = await backend.readCachedQuery(
        FeatureId.spoc,
        query,
        route == 'direct' ? RoutePolicy.direct : RoutePolicy.webvpn,
      );
      expect(cached.projection != null, isTrue);
      expect(cached.projection!.complete, isTrue);
      expect(cached.projection!.details.length, 1);
      expect(cached.projection!.details.single.actions.isEmpty, isTrue);
      expect(backend.recoveries, 0);
      expect(backend.commits, 0);
      debugPrint(
        'SPOC详情只读 route=$route prefix_batches=$prefixes detail_ms=$detailMs cacheReopen=true cacheComplete=true businessWrites=0 processCold=false',
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
