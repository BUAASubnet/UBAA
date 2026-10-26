part of 'shell.dart';

extension UbaaShellWriteActions on _UbaaMainShellState {
  WriteIntent? get _pendingWriteForDisplay =>
      (_homeSigninActive &&
              widget.writeState.intent?.operation ==
                  WriteOperation.signinPerform) ||
          (_bykcWriteActive != null &&
              widget.writeState.intent?.operation == _bykcWriteActive!.$1)
      ? null
      : widget.writeState.intent;

  bool get _hasWriteCommands =>
      widget.onRunWritePrepare != null &&
      widget.onCancelWrite != null &&
      widget.onConfirmWrite != null;

  bool get _hasYgdkSubmissionCapabilities =>
      _hasWriteCommands &&
      widget.onPrepareYgdkSubmitWrite != null &&
      widget.onPickYgdkPhoto != null &&
      widget.onRefreshYgdkAfterWrite != null &&
      widget.onCommitWrite != null &&
      widget.onDiscardWriteIntent != null;

  Widget _withCancelConfirmation({required Widget child, WriteIntent? intent}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: intent != null,
          child: ExcludeSemantics(excluding: intent != null, child: child),
        ),
        if (intent != null) ...[
          const ModalBarrier(dismissible: false, color: Colors.black54),
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () {
                if (!widget.writeState.isSubmitting) unawaited(_cancelWrite());
              },
            },
            child: FocusScope(
              autofocus: true,
              child: WriteConfirmationView(
                key: ValueKey(intent.intentId),
                intent: intent,
                onCancel: _cancelWrite,
                onConfirm: _confirmWrite,
                isSubmitting: widget.writeState.isSubmitting,
                isDiscarding: widget.writeState.isDiscarding,
                error: widget.writeState.error,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _startBykcWrite(WriteOperation operation, int courseId) async {
    final run = widget.onRunWritePrepare;
    final prepare = widget.onPrepareBykcWrite;
    final confirm = widget.onConfirmWrite;
    if (_bykcWriteActive != null ||
        widget.writeState.isSubmitting ||
        widget.writeState.intent != null ||
        !_hasWriteCommands ||
        run == null ||
        prepare == null ||
        confirm == null ||
        courseId <= 0 ||
        !const {
          WriteOperation.bykcSelectCourse,
          WriteOperation.bykcDeselectCourse,
        }.contains(operation))
      return;
    final generation = _accountGeneration;
    final policy = widget.routePolicy;
    final page = _readPageKeys[FeatureId.bykc]?.currentState;
    var attempted = false;
    WriteIntent? intent;
    _setBykcWriteActive((operation, courseId));
    page?.beginBykcCourseWrite();
    try {
      intent = await run(
        () => prepare(operation, courseId),
        expectedOperation: operation,
      );
      if (!mounted ||
          generation != _accountGeneration ||
          policy != widget.routePolicy ||
          intent == null)
        return;
      attempted = true;
      final outcome = await confirm();
      if (!mounted || generation != _accountGeneration) return;
      if (outcome != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(outcome.message)));
      }
    } on Object {
      if (mounted && generation == _accountGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              attempted ? '操作结果未确认，请刷新课程状态后核对。' : '未能提交，请刷新课程状态后重试。',
            ),
          ),
        );
      }
    } finally {
      // 过期或失效的准备结果不能在直接操作结束后变成意外确认页。
      if (mounted &&
          generation == _accountGeneration &&
          intent != null &&
          widget.writeState.intent?.intentId == intent.intentId &&
          !widget.writeState.isSubmitting) {
        await _cancelWrite();
      }
      try {
        if (mounted && generation == _accountGeneration) {
          await page?.finishBykcCourseWrite(refresh: attempted);
        }
      } on Object {
        if (mounted && generation == _accountGeneration) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('课程状态刷新失败，请手动刷新后核对。')));
        }
      } finally {
        if (mounted) _setBykcWriteActive(null);
      }
    }
  }

  Future<void> _startBykcSignWrite(BykcSignAction action) async {
    final prepare = widget.onPrepareBykcSignWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备博雅签到；未提交，请重试。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startSigninWrite(SigninPerformAction action) async {
    final prepare = widget.onPrepareSigninWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备签到；未提交，请重试。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startCgyyCancelWrite(CgyyCancelAction action) async {
    final prepare = widget.onPrepareCgyyCancelWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备取消研讨室订单；未提交，请重试。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startLibbookReserveWrite(LibbookReserveAction action) async {
    final prepare = widget.onPrepareLibbookReserveWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备图书馆预约；未提交，请重试。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startLibbookCancelWrite(LibbookCancelAction action) async {
    final prepare = widget.onPrepareLibbookCancelWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(action),
      failureMessage: '暂时无法准备取消图书馆预约；未提交，请重试。',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startEvaluation(List<EvaluationSubmitTarget> targets) async {
    final prepare = widget.onPrepareEvaluationWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(targets),
      failureMessage: '暂时无法准备教学评教；未提交，请重试。',
      expectedOperation: WriteOperation.evaluationSubmitCourses,
    );
  }

  Future<void> _startYgdkSubmitWrite(YgdkSubmitInput input) async {
    final prepare = widget.onPrepareYgdkSubmitWrite;
    if (!_hasYgdkSubmissionCapabilities || prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(input),
      failureMessage: '暂时无法准备阳光打卡；未提交，请重试。',
      expectedOperation: WriteOperation.ygdkSubmit,
    );
  }

  Future<void> _startCgyySubmitWrite(CgyySubmitInput input) async {
    final prepare = widget.onPrepareCgyySubmitWrite;
    if (prepare == null) return;
    await _prepareWrite(
      prepare: () => prepare(input),
      failureMessage: '暂时无法准备研讨室预约；未提交，请重试。',
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
      ).showSnackBar(const SnackBar(content: Text('暂时无法打卡；未提交，请重试。')));
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

extension UbaaHomeSignin on _UbaaMainShellState {
  Future<WriteOutcome?> _performHomeSignin(SigninPerformAction action) async {
    final run = widget.onRunWritePrepare;
    final prepare = widget.onPrepareSigninWrite;
    final confirm = widget.onConfirmWrite;
    if (_homeSigninActive ||
        widget.writeState.isSubmitting ||
        widget.writeState.intent != null ||
        run == null ||
        prepare == null ||
        confirm == null ||
        action.eligibility != ActionEligibility.allowed ||
        action.scheduleId.trim().isEmpty)
      return null;
    final generation = _accountGeneration;
    _setHomeSigninActive(true);
    try {
      final intent = await run(
        () => prepare(action),
        expectedOperation: action.operation,
      );
      if (!mounted || generation != _accountGeneration || intent == null)
        return null;
      final outcome = await confirm();
      if (!mounted || generation != _accountGeneration) return null;
      if (outcome != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(outcome.message)));
      }
      return outcome;
    } on Object {
      if (mounted && generation == _accountGeneration) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('签到未完成，请刷新状态后重试。')));
      }
      return null;
    } finally {
      if (mounted) _setHomeSigninActive(false);
    }
  }
}
