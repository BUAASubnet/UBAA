part of '../write_coordinator_test.dart';

void _registerInvalidationTests() {
  test('待确认通知同步失效后不返回旧意图且只释放一次', () async {
    final discarded = <String>[];
    final coordinator = WriteCoordinator(
      commit: (_) async => _result(),
      discard: (id) async => discarded.add(id),
      now: () => _now,
    );
    coordinator.addListener(() {
      if (coordinator.state.phase == WritePhase.ready) {
        coordinator.invalidate();
      }
    });
    expect(
      await coordinator.prepareForUi(
        () async => _intent(),
        expectedOperation: WriteOperation.bykcSelectCourse,
      ),
      isNull,
    );
    expect(discarded, <String>['intent-current']);
    coordinator.dispose();
  });

  test('完成通知同步失效后不交付旧完成消息', () async {
    var invalidated = false;
    final coordinator = WriteCoordinator(
      commit: (_) async => _result(),
      now: () => _now,
    );
    coordinator.setIntent(_intent());
    coordinator.addListener(() {
      if (!invalidated && coordinator.state.phase == WritePhase.idle) {
        invalidated = true;
        coordinator.invalidate();
      }
    });
    expect(await coordinator.confirmForUi(), isNull);
    expect(invalidated, isTrue);
    coordinator.dispose();
  });

  test('准备或取消错误通知同步失效后不抛过时错误', () async {
    for (final cancel in <bool>[false, true]) {
      final coordinator = WriteCoordinator(
        commit: (_) async => _result(),
        discard: (_) async => throw StateError('释放错误'),
        now: () => _now,
      );
      if (cancel) coordinator.setIntent(_intent());
      coordinator.addListener(() {
        if (coordinator.state.error != null) coordinator.invalidate();
      });
      if (cancel) {
        await coordinator.cancelForUi();
      } else {
        expect(
          await coordinator.prepareForUi(
            () async => throw StateError('准备错误'),
            expectedOperation: WriteOperation.bykcSelectCourse,
          ),
          isNull,
        );
      }
      expect(coordinator.error, isNull);
      coordinator.dispose();
    }
  });

  test('准备通知同步失效后不会调用旧 prepare', () async {
    var prepares = 0;
    final coordinator = WriteCoordinator(
      commit: (_) async => _result(),
      now: () => _now,
    );
    coordinator.addListener(() {
      if (coordinator.state.phase == WritePhase.preparing) {
        coordinator.invalidate();
      }
    });
    final prepared = await coordinator.prepareForUi(() async {
      prepares++;
      return _intent();
    }, expectedOperation: WriteOperation.bykcSelectCourse);
    expect(prepared, isNull);
    expect(prepares, 0);
    coordinator.dispose();
  });

  test('提交通知同步失效后零提交并释放未消费的意图', () async {
    var commits = 0;
    final discarded = <String>[];
    final coordinator = WriteCoordinator(
      commit: (_) async {
        commits++;
        return _result();
      },
      discard: (id) async => discarded.add(id),
      now: () => _now,
    );
    coordinator.setIntent(_intent());
    coordinator.addListener(() {
      if (coordinator.state.phase == WritePhase.committing) {
        coordinator.invalidate();
      }
    });
    expect(await coordinator.confirmForUi(), isNull);
    expect(commits, 0);
    expect(discarded, <String>['intent-current']);
    coordinator.dispose();
  });

  test('晚到 prepare 在失效后释放原意图且不能恢复确认页', () async {
    final prepared = Completer<WriteIntent>();
    final discarded = <String>[];
    final coordinator = WriteCoordinator(
      commit: (_) async => throw StateError('不应提交'),
      discard: (id) async => discarded.add(id),
      now: () => _now,
    );
    final preparing = coordinator.prepareForUi(
      () => prepared.future,
      expectedOperation: WriteOperation.bykcSelectCourse,
    );
    coordinator.invalidate();
    expect(coordinator.state.phase, WritePhase.invalidating);
    expect(
      await coordinator.prepareForUi(
        () async => _intent(id: 'new'),
        expectedOperation: WriteOperation.bykcSelectCourse,
      ),
      isNull,
    );
    prepared.complete(_intent());
    expect(await preparing, isNull);
    expect(discarded, <String>['intent-current']);
    expect(coordinator.state.phase, WritePhase.idle);
    coordinator.dispose();
  });

  test('待确认失效只释放一次且之后不能消费', () async {
    final discarded = <String>[];
    final coordinator = WriteCoordinator(
      commit: (_) async => throw StateError('不应提交'),
      discard: (id) async => discarded.add(id),
      now: () => _now,
    );
    coordinator.setIntent(_intent());
    coordinator.invalidate();
    coordinator.invalidate();
    await Future<void>.value();
    expect(discarded, <String>['intent-current']);
    expect(await coordinator.confirmForUi(), isNull);
    coordinator.dispose();
  });

  test('提交期间失效不回读不显示晚到结果且不补偿提交', () async {
    final result = Completer<WriteCommitResult>();
    var reads = 0;
    var discards = 0;
    final coordinator = WriteCoordinator(
      commit: (_) => result.future,
      discard: (_) async {
        discards++;
      },
      receiptVerifier: WriteReceiptVerifier(
        refreshAfterWrite: (_, _) async {
          reads++;
        },
      ),
      now: () => _now,
    );
    coordinator.setIntent(_intent());
    final confirming = coordinator.confirmForUi();
    coordinator.invalidate();
    result.complete(_result());
    expect(await confirming, isNull);
    expect(reads, 0);
    expect(discards, 0);
    expect(coordinator.intent, isNull);
    coordinator.dispose();
  });

  test('回读期间失效不执行第二次收据核对且不交付结果', () async {
    final refreshed = Completer<void>();
    var receiptChecks = 0;
    final coordinator = WriteCoordinator(
      commit: (_) async => _result(
        operation: WriteOperation.cgyySubmitReservation,
        receipt: const CgyyReservationReceipt(orderId: 42),
      ),
      receiptVerifier: WriteReceiptVerifier(
        refreshAfterWrite: (_, _) => refreshed.future,
        verifyCgyyReceipt: (_) async {
          receiptChecks++;
          return true;
        },
      ),
      now: () => _now,
    );
    coordinator.setIntent(
      _intent(operation: WriteOperation.cgyySubmitReservation),
    );
    final confirming = coordinator.confirmForUi();
    await Future<void>.value();
    expect(coordinator.state.phase, WritePhase.readingBack);
    coordinator.invalidate();
    refreshed.complete();
    expect(await confirming, isNull);
    expect(receiptChecks, 0);
    coordinator.dispose();
  });

  test('销毁后的 prepare 返回只清理且没有通知', () async {
    final prepared = Completer<WriteIntent>();
    var notifications = 0;
    final discarded = <String>[];
    final coordinator = WriteCoordinator(
      commit: (_) async => _result(),
      discard: (id) async {
        discarded.add(id);
        throw StateError('释放失败');
      },
      now: () => _now,
    );
    coordinator.addListener(() {
      notifications++;
    });
    final preparing = coordinator.prepare(() => prepared.future);
    coordinator.dispose();
    final before = notifications;
    prepared.complete(_intent());
    expect(await preparing, isNull);
    expect(notifications, before);
    expect(discarded, <String>['intent-current']);
  });

  test('取消期间失效不重复释放且晚到失败不恢复意图', () async {
    final released = Completer<void>();
    var discards = 0;
    final coordinator = WriteCoordinator(
      commit: (_) async => _result(),
      discard: (_) {
        discards++;
        return released.future;
      },
      now: () => _now,
    );
    coordinator.setIntent(_intent());
    final cancelling = coordinator.cancelForUi();
    coordinator.invalidate();
    released.completeError(StateError('过时的失败'));
    await cancelling;
    expect(discards, 1);
    expect(coordinator.intent, isNull);
    expect(coordinator.error, isNull);
    coordinator.dispose();
  });
}
