import 'package:meta/meta.dart';

import '../common/error.dart';
import 'intent.dart';

/// 写流程对 Host 与 UI 公开的封闭阶段。
enum WritePhase {
  idle,
  preparing,
  ready,
  cancelling,
  committing,
  readingBack,
  invalidating,
}

/// 写流程的不可变安全状态，由唯一协调器发布。
@immutable
class WriteState {
  const WriteState({required this.phase, this.intent, this.error});

  const WriteState.idle()
    : phase = WritePhase.idle,
      intent = null,
      error = null;

  final WritePhase phase;
  final WriteIntent? intent;
  final UiError? error;

  bool get isSubmitting =>
      phase != WritePhase.idle && phase != WritePhase.ready;

  bool get isDiscarding => phase == WritePhase.cancelling;
}

/// 提交及后续只读核对完成后的安全结果。
@immutable
class WriteOutcome {
  const WriteOutcome({
    required this.operation,
    required this.message,
    this.result,
    this.error,
    this.cgyyReceiptVerified,
    this.cgyyCancellationVerified,
    this.ygdkReadbackAttempted = false,
  }) : assert((result == null) != (error == null));

  final WriteOperation operation;
  final String message;
  final WriteCommitResult? result;
  final UiError? error;
  final bool? cgyyReceiptVerified;
  final bool? cgyyCancellationVerified;
  final bool ygdkReadbackAttempted;
}
