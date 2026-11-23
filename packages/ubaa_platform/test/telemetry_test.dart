import 'package:test/test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  group('TelemetryClient', () {
    test('功能打开只接受业务功能和固定维度', () async {
      final client = MockTelemetryClient();
      for (final feature in ['cloud_print', 'portal', 'network', 'agenda']) {
        await client.track(
          'feature_opened',
          properties: {
            'feature': feature,
            'route': 'none',
            'result': 'success',
            'bucket': 'lt_250',
            'source': 'package:ubaa_ui/src/app.dart:42',
          },
        );
      }
      expect(client.records.single.properties, {
        'feature': 'cloud_print',
        'route': 'none',
        'result': 'success',
      });
    });

    test('健康云打开事件仅保留固定维度', () async {
      final client = MockTelemetryClient();
      await client.track(
        TelemetryEvents.featureOpened,
        properties: const {
          'feature': 'health_cloud',
          'route': 'direct',
          'result': 'failure',
          'bucket': 'lt_250',
          'year': '2026',
        },
      );
      expect(client.records.single.properties, {
        'feature': 'health_cloud',
        'route': 'none',
        'result': 'success',
      });
    });

    test('无参客户端默认关闭且不调用 sink', () async {
      var calls = 0;
      final client = TelemetryClient(sink: (_) async => calls++);

      await client.track(
        TelemetryEvents.appStarted,
        properties: const {'platform': 'ios'},
      );
      expect(client.enabled, isFalse);
      expect(calls, 0);
    });

    test('Mock 只记录白名单事件和安全字段', () async {
      final client = MockTelemetryClient();

      await client.track(
        TelemetryEvents.authFailed,
        properties: const {
          'error_code': 'invalid_credentials',
          'retryable': false,
          'password': 'secret',
          'unknown': 'drop-me',
        },
      );
      await client.track('arbitrary_event', properties: const {});

      expect(client.records, hasLength(1));
      expect(client.records.single.name, TelemetryEvents.authFailed);
      expect(client.records.single.properties, <String, Object?>{
        'error_code': 'invalid_credentials',
        'retryable': false,
      });
      expect(client.records.single.toString(), isNot(contains('secret')));
    });

    test('Callback sink 的异常不会冒泡到业务层', () async {
      final client = CallbackTelemetryClient(
        sink: (_) => throw StateError('token=secret'),
      );

      await expectLater(client.track(TelemetryEvents.featureLoaded), completes);
    });

    test('白名单拒绝看似允许的字段中夹带的消息、路线策略和本机路径', () async {
      final client = MockTelemetryClient();
      await client.track(
        TelemetryEvents.authFailed,
        properties: const {
          'feature': 'auth',
          'error_code': 'network_error',
          'error_kind': 'network',
          'retryable': true,
          'route': 'auto',
          'source': '/private/example.dart:42',
          'result': '完整错误消息',
        },
      );
      expect(client.records.single.properties, {
        'feature': 'auth',
        'error_code': 'network_error',
        'error_kind': 'network',
        'retryable': true,
      });
    });

    test('自定义策略只能收窄事件和字段白名单', () async {
      final client = MockTelemetryClient(
        policy: TelemetryPolicy(
          allowedEvents: const {TelemetryEvents.featureLoaded, 'custom_event'},
          allowedFields: const {'feature', 'password', 'safe'},
        ),
      );

      await client.track(
        'custom_event',
        properties: const {'safe': 'ok', 'password': 'secret'},
      );
      await client.track(
        TelemetryEvents.featureLoaded,
        properties: const {
          'feature': 'schedule',
          'safe': 'drop-me',
          'password': 'secret',
        },
      );
      expect(client.records, hasLength(1));
      expect(client.records.single.properties, <String, Object?>{
        'feature': 'schedule',
      });
    });
  });
}
