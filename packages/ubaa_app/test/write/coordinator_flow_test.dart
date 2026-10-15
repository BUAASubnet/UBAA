import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../support/write/fixtures.dart'
    show fixtureIntent, fixtureNow, fixtureResult;

void _registerFlowTests() {
  test('旧接口对所有 BackendException 保留原错误码而安全状态按 UI 映射', () async {
    for (final code in UbaaErrorCode.values) {
      for (final operation in <String>['prepare', 'cancel', 'confirm']) {
        final coordinator = WriteFlowController(
          commit: (_) async =>
              throw BackendException(code, detail: '/private/token=secret'),
          discard: (_) async =>
              throw BackendException(code, detail: '/private/token=secret'),
          now: () => fixtureNow,
        );
        if (operation != 'prepare') coordinator.setIntent(fixtureIntent());
        final future = switch (operation) {
          'prepare' => coordinator.prepare(
            () async =>
                throw BackendException(code, detail: '/private/token=secret'),
          ),
          'cancel' => coordinator.cancel(),
          _ => coordinator.confirm(),
        };
        await expectLater(
          future,
          throwsA(
            isA<BackendException>()
                .having((error) => error.code, 'code/$operation', code)
                .having((error) => error.detail, 'detail/$operation', isNull),
          ),
        );
        expect(coordinator.error?.code, UbaaErrorMapper.fromCode(code).code);
        coordinator.dispose();
      }
    }
  });

  test('会话转换门禁关闭时不准备或提交且重新开放后可继续', () async {
    var available = true;
    var prepares = 0;
    var commits = 0;
    final coordinator = WriteCoordinator(
      commit: (_) async {
        commits++;
        return fixtureResult();
      },
      canStart: () => available,
      now: () => fixtureNow,
    );
    coordinator.setIntent(fixtureIntent());
    available = false;
    expect(await coordinator.confirmForUi(), isNull);
    coordinator.invalidate();
    coordinator.setIntent(fixtureIntent(id: 'not-allowed'));
    expect(coordinator.intent, isNull);
    expect(
      await coordinator.prepareForUi(() async {
        prepares++;
        return fixtureIntent();
      }, expectedOperation: WriteOperation.bykcSelectCourse),
      isNull,
    );
    expect(prepares, 0);
    expect(commits, 0);
    available = true;
    expect(
      await coordinator.prepareForUi(() async {
        prepares++;
        return fixtureIntent();
      }, expectedOperation: WriteOperation.bykcSelectCourse),
      isNotNull,
    );
    expect((await coordinator.confirmForUi())?.result?.success, isTrue);
    expect(prepares, 1);
    expect(commits, 1);
    coordinator.dispose();
  });

  test('旧控制器名称与新协调器使用同一类型和状态', () {
    final WriteFlowController legacy = WriteCoordinator(
      commit: (_) async => fixtureResult(),
      now: () => fixtureNow,
    );
    expect(legacy.runtimeType, WriteCoordinator);
    legacy.setIntent(fixtureIntent());
    expect(legacy.intent, same(legacy.state.intent));
    legacy.dispose();
  });

  test('准备期间阻止重入并在返回后发布不可变待确认状态', () async {
    final prepared = Completer<WriteIntent>();
    var calls = 0;
    final coordinator = WriteCoordinator(
      commit: (_) async => throw StateError('尚未确认'),
      now: () => fixtureNow,
    );
    final initial = coordinator.state;
    final first = coordinator.prepareForUi(() {
      calls++;
      return prepared.future;
    }, expectedOperation: WriteOperation.bykcSelectCourse);
    expect(coordinator.state.phase, WritePhase.preparing);
    expect(
      await coordinator.prepareForUi(() async {
        calls++;
        return fixtureIntent(id: 'duplicate');
      }, expectedOperation: WriteOperation.bykcSelectCourse),
      isNull,
    );
    prepared.complete(fixtureIntent());
    expect(await first, same(coordinator.intent));
    expect(calls, 1);
    expect(initial.phase, WritePhase.idle);
    expect(coordinator.state.phase, WritePhase.ready);
    coordinator.dispose();
  });

  test('所有入口都拒绝 prepare 返回不匹配的操作并释放一次', () async {
    for (final operation in WriteOperation.values) {
      final discarded = <String>[];
      final coordinator = WriteCoordinator(
        commit: (_) async => throw StateError('不应提交'),
        discard: (id) async => discarded.add(id),
        now: () => fixtureNow,
      );
      final wrong = operation == WriteOperation.bykcSelectCourse
          ? WriteOperation.signinPerform
          : WriteOperation.bykcSelectCourse;
      await expectLater(
        coordinator.prepareForUi(
          () async => fixtureIntent(operation: wrong),
          expectedOperation: operation,
        ),
        throwsA(
          isA<UiError>().having(
            (error) => error.code,
            'code',
            UbaaErrorCode.internalError,
          ),
        ),
      );
      expect(discarded, <String>['intent-current']);
      expect(coordinator.intent, isNull);
      coordinator.dispose();
    }
  });

  test('准备与取消的 UI 入口只抛过滤后的 UiError', () async {
    final coordinator = WriteCoordinator(
      commit: (_) async => fixtureResult(),
      discard: (_) async => throw const BackendException(
        UbaaErrorCode.networkError,
        detail: '/private/token=secret',
      ),
      now: () => fixtureNow,
    );
    await expectLater(
      coordinator.prepareForUi(
        () async => throw StateError('/private/token=secret'),
        expectedOperation: WriteOperation.bykcSelectCourse,
      ),
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.internalError,
        ),
      ),
    );
    coordinator.setIntent(fixtureIntent());
    await expectLater(
      coordinator.cancelForUi(),
      throwsA(
        isA<UiError>().having(
          (error) => error.code,
          'code',
          UbaaErrorCode.networkError,
        ),
      ),
    );
    expect(coordinator.state.phase, WritePhase.ready);
    expect(coordinator.state.intent?.intentId, 'intent-current');
    expect(coordinator.error.toString(), isNot(contains('secret')));
    coordinator.dispose();
  });

  test('取消期间不可确认且释放完成后才清理', () async {
    final release = Completer<void>();
    var commits = 0;
    final coordinator = WriteCoordinator(
      commit: (_) async {
        commits++;
        return fixtureResult();
      },
      discard: (_) => release.future,
      now: () => fixtureNow,
    );
    coordinator.setIntent(fixtureIntent());
    final cancelling = coordinator.cancelForUi();
    expect(coordinator.state.isDiscarding, isTrue);
    expect(coordinator.intent, isNotNull);
    expect(await coordinator.confirmForUi(), isNull);
    release.complete();
    await cancelling;
    expect(coordinator.intent, isNull);
    expect(commits, 0);
    coordinator.dispose();
  });

  test('提交开始后双击确认只调用一次且未知异常消费意图', () async {
    final release = Completer<WriteCommitResult>();
    var calls = 0;
    final coordinator = WriteCoordinator(
      commit: (_) {
        calls++;
        return release.future;
      },
      now: () => fixtureNow,
    );
    coordinator.setIntent(fixtureIntent());
    final first = coordinator.confirmForUi();
    expect(coordinator.state.phase, WritePhase.committing);
    expect(await coordinator.confirmForUi(), isNull);
    coordinator.setIntent(fixtureIntent(id: 'replacement'));
    release.completeError(StateError('/private/token=secret'));
    final outcome = await first;
    expect(calls, 1);
    expect(outcome?.error?.code, UbaaErrorCode.outcomeUnknown);
    expect(outcome?.message, '提交结果不确定，请先刷新相关状态，不要重复提交。');
    expect(coordinator.intent, isNull);
    expect(await coordinator.confirmForUi(), isNull);
    coordinator.dispose();
  });

  test('旧 confirm 过滤未知异常、消费意图且不能重复提交', () async {
    var commits = 0;
    final coordinator = WriteFlowController(
      commit: (_) async {
        commits++;
        throw StateError('/private/token=secret');
      },
      now: () => fixtureNow,
    );
    coordinator.setIntent(fixtureIntent());
    await expectLater(
      coordinator.confirm(),
      throwsA(
        isA<BackendException>()
            .having((error) => error.code, 'code', UbaaErrorCode.outcomeUnknown)
            .having((error) => error.detail, 'detail', isNull),
      ),
    );
    expect(coordinator.intent, isNull);
    expect(await coordinator.confirm(), isNull);
    expect(commits, 1);
    coordinator.dispose();
  });

  test('过期精确边界不提交且仍可取消', () async {
    var commits = 0;
    final discarded = <String>[];
    final coordinator = WriteCoordinator(
      commit: (_) async {
        commits++;
        return fixtureResult();
      },
      discard: (id) async => discarded.add(id),
      now: () => fixtureNow,
    );
    coordinator.setIntent(fixtureIntent(expiresAt: fixtureNow));
    expect(await coordinator.confirmForUi(), isNull);
    expect(commits, 0);
    expect(coordinator.error?.code, UbaaErrorCode.intentExpired);
    await coordinator.cancelForUi();
    expect(discarded, <String>['intent-current']);
    coordinator.dispose();
  });

  test('确定业务失败保持结果而不是异常且不可重复提交', () async {
    final result = fixtureResult(success: false);
    final coordinator = WriteCoordinator(
      commit: (_) async => result,
      now: () => fixtureNow,
    );
    coordinator.setIntent(fixtureIntent());
    final outcome = await coordinator.confirmForUi();
    expect(outcome?.result, same(result));
    expect(outcome?.error, isNull);
    expect(await coordinator.confirmForUi(), isNull);
    coordinator.dispose();
  });
}

void main() {
  _registerFlowTests();
}
