import 'dart:async';
import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('日程失败报告原始异常且过期账号不产生记录', () async {
    for (final stale in [false, true]) {
      final backend = _Backend();
      final failures = <Object>[];
      final service = AgendaService(backend)
        ..onFailure = (error, stack) {
          expect(stack.toString(), isNotEmpty);
          failures.add(error);
        };
      await service.openAccount('known-alias');
      final pending = service.unsyncedCount();
      final result = expectLater(pending, throwsA(isA<AgendaException>()));
      await backend.started.future;
      if (stale) await service.close();
      const error = AgendaException(AgendaFailure.corrupt);
      backend.result.completeError(error, StackTrace.current);
      await result;
      expect(failures, stale ? isEmpty : [same(error)]);
      await service.dispose();
    }
  });

  test('退出立即撤销访问并拒绝迟到查询，重新登录沿用账号', () async {
    final backend = _Backend();
    final service = AgendaService(backend);
    await service.openAccount('known-alias');
    final result = service.unsyncedCount();
    await backend.started.future;
    final expectation = expectLater(
      result,
      throwsA(
        isA<AgendaException>().having(
          (e) => e.failure,
          '类别',
          AgendaFailure.superseded,
        ),
      ),
    );
    await service.close();
    backend.result.complete(3);
    await expectation;
    await expectLater(service.unsyncedCount(), throwsA(isA<AgendaException>()));
    await service.openAccount('known-alias');
    expect(backend.accounts, ['known-alias', 'known-alias']);
    expect(await service.unsyncedCount(), 3);
    await service.dispose();
    await expectLater(
      service.openAccount('another'),
      throwsA(isA<AgendaException>()),
    );
  });
  test('打开期间退出仍关闭迟到句柄，错误不会带回旧账号', () async {
    final backend = _Backend()..openGate = Completer<void>();
    final service = AgendaService(backend);
    final opening = service.openAccount('known-alias');
    final expectation = expectLater(opening, throwsA(isA<AgendaException>()));
    await Future<void>.delayed(Duration.zero);
    final closing = service.close();
    backend.openGate!.complete();
    await expectation;
    await closing;
    expect(backend.active, isFalse);
    expect(service.accountId, isNull);
  });
}

class _Backend implements AgendaBackend {
  final accounts = <String>[];
  final started = Completer<void>();
  final result = Completer<int>();
  Completer<void>? openGate;
  bool active = false;
  @override
  Future<void> openAccount(String alias) async {
    accounts.add(alias);
    await openGate?.future;
    active = true;
  }

  @override
  Future<void> deactivate() async {
    active = false;
  }

  @override
  Future<int> unsyncedCount() async {
    if (!started.isCompleted) started.complete();
    return result.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
