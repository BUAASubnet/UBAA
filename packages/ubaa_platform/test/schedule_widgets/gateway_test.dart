import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.buaa.ubaa/schedule-widgets');
  final calls = <MethodCall>[];
  Object? beginReply;
  setUp(() {
    calls.clear();
    beginReply = 'scope-1';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'begin') return beginReply;
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  final snapshot = ScheduleWidgetSnapshot(
    owner: 'owner-1',
    semesters: const [],
  );

  for (final (name, gateway) in [
    ('iOS', IOSScheduleWidgetGateway()),
    ('Android', AndroidScheduleWidgetGateway()),
  ]) {
    test('$name 网关在同一通道发布课表快照', () async {
      final scope = await gateway.begin('owner-1');
      expect(scope, 'scope-1');
      await gateway.publish('scope-1', snapshot);
      expect(calls.map((c) => c.method), ['begin', 'publish']);
      final begin = calls.first.arguments as Map;
      expect(begin['owner'], 'owner-1');
      final publish = calls.last.arguments as Map;
      expect(publish['scope'], 'scope-1');
      expect(publish['snapshot'], snapshot.toJson());
    });

    test('$name 网关在原生端无组件时抛出 widget_unavailable', () async {
      beginReply = null;
      await expectLater(
        gateway.begin('owner-1'),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'widget_unavailable',
          ),
        ),
      );
    });
  }
}
