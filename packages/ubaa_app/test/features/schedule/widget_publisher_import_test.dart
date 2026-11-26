import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  testWidgets('换号撤销失败后，下一次更新立即重试，成功后才读取快照', (tester) async {
    final gateway = _Gateway();
    final publisher = ScheduleWidgetPublisher(gateway);
    addTearDown(publisher.dispose);
    await publisher.update(
      'a',
      (_) async => ScheduleWidgetSnapshot(owner: 'a', semesters: []),
    );
    gateway.fail = true;
    await expectLater(
      publisher.update('b', (_) async => fail('撤销失败不能读取')),
      throwsStateError,
    );
    gateway.fail = false;
    final snapshot = Completer<ScheduleWidgetSnapshot>();
    List<String?>? ownersAtRead;
    final retry = publisher.update('b', (_) {
      ownersAtRead = [...gateway.owners];
      return snapshot.future;
    });
    await tester.pump();
    expect(gateway.owners, ['a', 'b']);
    expect(ownersAtRead, ['a', 'b']);
    snapshot.complete(ScheduleWidgetSnapshot(owner: 'b', semesters: []));
    await retry;
    expect(gateway.published, ['a', 'b']);
  });
  testWidgets('释放取消待构建快照，已请求的退出撤销仍然交付', (tester) async {
    final gateway = _Gateway(), publisher = ScheduleWidgetPublisher(gateway);
    await publisher.update(
      '合成账号',
      (_) async => ScheduleWidgetSnapshot(owner: '合成账号', semesters: []),
    );
    final waiting = publisher.update('合成账号', (_) async => fail('已取消的防抖不能读取'));
    final revoke = publisher.update(null, (_) async => fail('退出不能读取'));
    publisher.dispose();
    await tester.pump(const Duration(seconds: 2));
    await Future.wait([waiting, revoke]);
    expect(gateway.owners, ['合成账号', null]);
    expect(gateway.published, ['合成账号']);
  });
  testWidgets('同账号修订防抖，内容不变不申请原生代次', (tester) async {
    final gateway = _Gateway();
    final publisher = ScheduleWidgetPublisher(gateway);
    var reads = 0;
    Future<ScheduleWidgetSnapshot> read(bool Function() current) async {
      reads++;
      return ScheduleWidgetSnapshot(owner: '合成账号', semesters: []);
    }

    await publisher.update('合成账号', read);
    final first = publisher.update('合成账号', read);
    await tester.pump(const Duration(seconds: 1));
    final second = publisher.update('合成账号', read);
    await tester.pump(const Duration(milliseconds: 1499));
    expect(reads, 1);
    await tester.pump(const Duration(milliseconds: 1));
    await Future.wait([first, second]);
    expect(reads, 2);
    expect(gateway.owners, ['合成账号']);
    expect(gateway.published, ['合成账号']);
    publisher.dispose();
  });
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
