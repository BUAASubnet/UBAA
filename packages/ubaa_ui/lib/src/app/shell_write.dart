part of '../widgets.dart';

extension _UbaaShellWriteActions on _UbaaMainShellState {
  Future<void> _startBykcWrite(WriteOperation operation, int courseId) async {
    final prepare = widget.onPrepareBykcWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(operation, courseId),
      expectedOperation: operation,
      failureMessage: '暂时无法准备操作；尚未提交任何写请求。',
    );
  }

  Future<void> _startBykcSignWrite(BykcSignAction action) async {
    final prepare = widget.onPrepareBykcSignWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备博雅签到；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startSigninWrite(SigninPerformAction action) async {
    final prepare = widget.onPrepareSigninWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备签到；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startCgyyCancelWrite(CgyyCancelAction action) async {
    final prepare = widget.onPrepareCgyyCancelWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备取消研讨室订单；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startLibbookReserveWrite(LibbookReserveAction action) async {
    final prepare = widget.onPrepareLibbookReserveWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备图书馆预约；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startLibbookCancelWrite(LibbookCancelAction action) async {
    final prepare = widget.onPrepareLibbookCancelWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备取消图书馆预约；尚未提交任何写请求。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startEvaluation(List<EvaluationSubmitTarget> targets) async {
    final prepare = widget.onPrepareEvaluationWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(targets),
      failureMessage: '暂时无法准备教学评教；尚未提交任何写请求。',
      expectedOperation: WriteOperation.evaluationSubmitCourses,
    );
  }

  Future<void> _startYgdkSubmitWrite(YgdkSubmitInput input) async {
    final prepare = widget.onPrepareYgdkSubmitWrite;
    if (!_hasYgdkSubmissionCapabilities || prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(input),
      failureMessage: '暂时无法准备阳光打卡；尚未提交任何写请求。',
      expectedOperation: WriteOperation.ygdkSubmit,
    );
  }

  Future<void> _startCgyySubmitWrite(CgyySubmitInput input) async {
    final prepare = widget.onPrepareCgyySubmitWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(input),
      failureMessage: '暂时无法准备研讨室预约；尚未提交任何写请求。',
      expectedOperation: WriteOperation.cgyySubmitReservation,
    );
  }

  Future<void> _prepareWrite({
    required Future<WriteIntent> Function() prepare,
    required String failureMessage,
    required WriteOperation expectedOperation,
  }) async {
    final run = widget.onRunWritePrepare;
    if (!_hasWriteCommands || run == null || widget.writeState.isSubmitting) {
      return;
    }
    try {
      await run(prepare, expectedOperation: expectedOperation);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }

  Future<void> _cancelWrite() async {
    final cancel = widget.onCancelWrite;
    if (cancel == null || widget.writeState.isSubmitting) return;
    try {
      await cancel();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂时无法取消待确认操作，请重试。')));
    }
  }

  Future<void> _confirmWrite() async {
    final intent = widget.writeState.intent;
    if (intent == null || widget.writeState.isSubmitting) return;
    if (intent.operation == WriteOperation.ygdkSubmit &&
        !_hasYgdkSubmissionCapabilities) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('阳光打卡能力不完整；尚未提交任何写请求。')));
      return;
    }
    final confirm = widget.onConfirmWrite;
    if (confirm == null) return;
    final outcome = await confirm();
    if (!mounted || outcome == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(outcome.message)));
  }
}
