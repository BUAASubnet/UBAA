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
    WriteOutcome? outcome;
    String? failure;
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
      outcome = await confirm();
    } on Object {
      if (mounted && generation == _accountGeneration) {
        failure = attempted ? '结果待核实，请刷新后确认，勿重复提交' : '未能提交，请刷新后重试';
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
        if (mounted &&
            generation == _accountGeneration &&
            policy == widget.routePolicy) {
          final refreshed = await page?.finishBykcCourseWrite(
            refresh: attempted,
          );
          if (!mounted ||
              generation != _accountGeneration ||
              policy != widget.routePolicy)
            return;
          if (failure != null) {
            UbaaFeedback.show(context, failure, kind: UbaaFeedbackKind.warning);
          } else if (outcome != null) {
            final success =
                outcome.result?.success == true &&
                outcome.result?.outcomeUnknown != true;
            final label = operation == WriteOperation.bykcSelectCourse
                ? '选课'
                : '退选';
            UbaaFeedback.show(
              context,
              success
                  ? (refreshed == true ? '$label成功' : '$label成功，列表暂未更新')
                  : outcome.message,
              kind: success && refreshed == true
                  ? UbaaFeedbackKind.success
                  : UbaaFeedbackKind.warning,
            );
          }
        }
      } on Object {
        if (mounted && generation == _accountGeneration) {
          UbaaFeedback.show(
            context,
            '列表暂未更新，请刷新后核对',
            kind: UbaaFeedbackKind.warning,
          );
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
      UbaaFeedback.show(context, failureMessage, kind: UbaaFeedbackKind.error);
    }
  }

  Future<void> _cancelWrite() async {
    final cancel = widget.onCancelWrite;
    if (cancel == null || widget.writeState.isSubmitting) return;
    try {
      await cancel();
    } on Object {
      if (!mounted) return;
      UbaaFeedback.show(
        context,
        '暂时无法取消待确认操作，请重试。',
        kind: UbaaFeedbackKind.error,
      );
    }
  }

  Future<void> _confirmWrite() async {
    final intent = widget.writeState.intent;
    if (intent == null || widget.writeState.isSubmitting) return;
    if (intent.operation == WriteOperation.ygdkSubmit &&
        !_hasYgdkSubmissionCapabilities) {
      UbaaFeedback.show(
        context,
        '暂时无法打卡；未提交，请重试。',
        kind: UbaaFeedbackKind.error,
      );
      return;
    }
    final confirm = widget.onConfirmWrite;
    if (confirm == null) return;
    final outcome = await confirm();
    if (!mounted || outcome == null) return;
    UbaaFeedback.showOutcome(context, outcome);
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
        UbaaFeedback.showOutcome(context, outcome);
      }
      return outcome;
    } on Object {
      if (mounted && generation == _accountGeneration) {
        UbaaFeedback.show(
          context,
          '签到未完成，请刷新状态后重试。',
          kind: UbaaFeedbackKind.error,
        );
      }
      return null;
    } finally {
      if (mounted) _setHomeSigninActive(false);
    }
  }
}
