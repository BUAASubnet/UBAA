import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('空闲写状态不保留意图、错误或忙碌标记', () {
    const state = WriteState.idle();

    expect(state.phase, WritePhase.idle);
    expect(state.intent, isNull);
    expect(state.error, isNull);
    expect(state.isSubmitting, isFalse);
    expect(state.isDiscarding, isFalse);
  });

  test('写阶段为界面提供统一的忙碌与取消标记', () {
    const expectations = <(WritePhase, bool, bool)>[
      (WritePhase.idle, false, false),
      (WritePhase.preparing, true, false),
      (WritePhase.ready, false, false),
      (WritePhase.cancelling, true, true),
      (WritePhase.committing, true, false),
      (WritePhase.readingBack, true, false),
      (WritePhase.invalidating, true, false),
    ];

    for (final (phase, submitting, discarding) in expectations) {
      final state = WriteState(phase: phase);

      expect(state.isSubmitting, submitting, reason: phase.name);
      expect(state.isDiscarding, discarding, reason: phase.name);
    }
  });

  test('写状态保留确认意图与安全错误', () {
    final intent = WriteIntent(
      intentId: 'intent-safe',
      operation: WriteOperation.bykcSelectCourse,
      targetSummary: '脱敏课程',
      resolvedRoute: ConnectionMode.direct,
      warnings: const <String>[],
      expiresAt: DateTime.utc(2026, 9, 5, 12),
      requestDigest: 'digest-safe',
    );
    final state = WriteState(
      phase: WritePhase.ready,
      intent: intent,
      error: _error,
    );

    expect(state.intent, same(intent));
    expect(state.error, same(_error));
  });

  test('成功完成结果默认不声明领域回读结论', () {
    const outcome = WriteOutcome(
      operation: WriteOperation.cgyySubmitReservation,
      message: '提交完成',
      result: _result,
    );

    expect(outcome.operation, WriteOperation.cgyySubmitReservation);
    expect(outcome.message, '提交完成');
    expect(outcome.result, same(_result));
    expect(outcome.error, isNull);
    expect(outcome.cgyyReceiptVerified, isNull);
    expect(outcome.cgyyCancellationVerified, isNull);
    expect(outcome.ygdkReadbackAttempted, isFalse);
  });

  test('失败完成结果可以保留独立的领域回读结论', () {
    const outcome = WriteOutcome(
      operation: WriteOperation.ygdkSubmit,
      message: '提交结果待核对',
      error: _error,
      cgyyReceiptVerified: false,
      cgyyCancellationVerified: true,
      ygdkReadbackAttempted: true,
    );

    expect(outcome.result, isNull);
    expect(outcome.error, same(_error));
    expect(outcome.cgyyReceiptVerified, isFalse);
    expect(outcome.cgyyCancellationVerified, isTrue);
    expect(outcome.ygdkReadbackAttempted, isTrue);
  });

  test('完成结果拒绝同时缺少提交结果和错误', () {
    expect(
      () => WriteOutcome(
        operation: WriteOperation.cgyySubmitReservation,
        message: '缺少结果',
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('完成结果拒绝同时包含提交结果和错误', () {
    expect(
      () => WriteOutcome(
        operation: WriteOperation.cgyySubmitReservation,
        message: '冲突结果',
        result: _result,
        error: _error,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}

const _result = WriteCommitResult(
  operation: WriteOperation.cgyySubmitReservation,
  success: true,
  message: '提交完成',
  outcomeUnknown: false,
);

const _error = UiError(
  code: UbaaErrorCode.outcomeUnknown,
  title: '结果未知',
  message: '请核对结果',
);
