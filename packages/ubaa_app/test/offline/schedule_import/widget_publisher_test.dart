import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('账号变化先开始新scope且A迟到投影不能覆盖B', () async {
    final gateway = _Gateway();
    final publisher = ScheduleWidgetPublisher(gateway);
    final a = Completer<ScheduleWidgetSnapshot>();
    final started = Completer<void>();
    final first = publisher.update('a', (_) {
      started.complete();
      return a.future;
    });
    await started.future;
    await publisher.update(
      'b',
      (_) async => ScheduleWidgetSnapshot(owner: 'b', semesters: []),
    );
    a.complete(ScheduleWidgetSnapshot(owner: 'a', semesters: []));
    await first;
    expect(gateway.owners, ['a', 'b']);
    expect(gateway.published, ['b']);
    await publisher.update(null, (_) => throw StateError('退出不能读课表'));
    expect(gateway.owners.last, isNull);
  });
  test('系统存储失败不发布明文或冒充成功，后续显式更新可恢复', () async {
    final gateway = _Gateway()..fail = true;
    final publisher = ScheduleWidgetPublisher(gateway);
    await expectLater(
      publisher.update(
        'a',
        (_) async => ScheduleWidgetSnapshot(owner: 'a', semesters: []),
      ),
      throwsStateError,
    );
    expect(gateway.published, isEmpty);
    gateway.fail = false;
    await publisher.update(
      'a',
      (_) async => ScheduleWidgetSnapshot(owner: 'a', semesters: []),
    );
    expect(gateway.published, ['a']);
  });
}

class _Gateway implements ScheduleWidgetGateway {
  final owners = <String?>[], published = <String>[];
  bool fail = false;
  @override
  Future<String> begin(String? owner) async {
    if (fail) throw StateError('合成存储失败');
    owners.add(owner);
    return owners.length.toString();
  }

  @override
  Future<void> publish(String scope, ScheduleWidgetSnapshot snapshot) async {
    expect(scope, owners.length.toString());
    published.add(snapshot.owner);
  }
}
