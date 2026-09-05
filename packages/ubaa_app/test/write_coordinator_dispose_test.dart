import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  for (final fails in <bool>[false, true]) {
    final completion = fails ? '失败' : '成功';

    test('取消等待期间销毁后，晚到$completion不重复释放或通知', () async {
      final released = Completer<void>();
      var discards = 0;
      var notifications = 0;
      final coordinator = WriteCoordinator(
        commit: (_) async => throw StateError('不应提交'),
        discard: (_) {
          discards++;
          return released.future;
        },
        now: () => _now,
      );
      coordinator.addListener(() => notifications++);
      coordinator.setIntent(_intent());
      final cancelling = coordinator.cancelForUi();
      expect(coordinator.state.phase, WritePhase.cancelling);
      expect(discards, 1);

      coordinator.dispose();
      final before = notifications;
      if (fails) {
        released.completeError(StateError('过时的释放失败'));
      } else {
        released.complete();
      }
      await cancelling;

      expect(discards, 1);
      expect(notifications, before);
      expect(coordinator.state.phase, WritePhase.idle);
      expect(coordinator.intent, isNull);
      expect(coordinator.error, isNull);
      expect(await coordinator.confirmForUi(), isNull);
    });

    test('提交等待期间销毁后，晚到$completion不回读或交付结果', () async {
      final committed = Completer<WriteCommitResult>();
      var commits = 0;
      var discards = 0;
      var reads = 0;
      var notifications = 0;
      final coordinator = WriteCoordinator(
        commit: (_) {
          commits++;
          return committed.future;
        },
        discard: (_) async => discards++,
        receiptVerifier: WriteReceiptVerifier(
          refreshAfterWrite: (_, _) async => reads++,
        ),
        now: () => _now,
      );
      coordinator.addListener(() => notifications++);
      coordinator.setIntent(_intent());
      final confirming = coordinator.confirmForUi();
      expect(coordinator.state.phase, WritePhase.committing);
      expect(commits, 1);

      coordinator.dispose();
      final before = notifications;
      if (fails) {
        committed.completeError(StateError('过时的提交失败'));
      } else {
        committed.complete(_result());
      }

      expect(await confirming, isNull);
      expect(commits, 1);
      expect(discards, 0);
      expect(reads, 0);
      expect(notifications, before);
      expect(coordinator.state.phase, WritePhase.idle);
      expect(coordinator.intent, isNull);
      expect(coordinator.error, isNull);
      expect(await coordinator.confirmForUi(), isNull);
    });

    test('回读等待期间销毁后，晚到$completion不核对收据或交付结果', () async {
      final readStarted = Completer<void>();
      final refreshed = Completer<void>();
      var receiptChecks = 0;
      var notifications = 0;
      final coordinator = WriteCoordinator(
        commit: (_) async => _result(),
        receiptVerifier: WriteReceiptVerifier(
          refreshAfterWrite: (_, _) {
            readStarted.complete();
            return refreshed.future;
          },
          verifyCgyyReceipt: (_) async {
            receiptChecks++;
            return true;
          },
        ),
        now: () => _now,
      );
      coordinator.addListener(() => notifications++);
      coordinator.setIntent(_intent());
      final confirming = coordinator.confirmForUi();
      await readStarted.future;
      expect(coordinator.state.phase, WritePhase.readingBack);

      coordinator.dispose();
      final before = notifications;
      if (fails) {
        refreshed.completeError(StateError('过时的回读失败'));
      } else {
        refreshed.complete();
      }

      expect(await confirming, isNull);
      expect(receiptChecks, 0);
      expect(notifications, before);
      expect(coordinator.state.phase, WritePhase.idle);
      expect(coordinator.intent, isNull);
      expect(coordinator.error, isNull);
      expect(await coordinator.confirmForUi(), isNull);
    });
  }
}

final _now = DateTime.utc(2026, 9, 5, 9);

WriteIntent _intent() => WriteIntent(
  intentId: 'dispose-intent',
  operation: WriteOperation.cgyySubmitReservation,
  targetSummary: '销毁时序测试',
  resolvedRoute: ConnectionMode.direct,
  warnings: const <String>[],
  expiresAt: _now.add(const Duration(minutes: 2)),
  requestDigest: 'safe-digest',
);

WriteCommitResult _result() => const WriteCommitResult(
  operation: WriteOperation.cgyySubmitReservation,
  success: true,
  message: '已提交，请刷新核对',
  outcomeUnknown: false,
  resolvedRoute: ConnectionMode.direct,
  cgyyReceipt: CgyyReservationReceipt(orderId: 42),
);
