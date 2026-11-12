part of 'shell.dart';

extension UbaaShellWriteActions on _UbaaMainShellState {
  BykcAgendaContext? get _bykcAgendaContext =>
      widget.agenda.service == null && widget.agenda.failure == null
      ? null
      : BykcAgendaContext(
          access: widget.agenda,
          route: agendaRoute(
            widget.routePolicy,
            widget.activeRoutes,
            schoolRoute: widget.agendaSchoolRoute,
          ),
          epoch: (_contentEpoch, widget.readCacheEpoch, widget.agendaEpoch),
        );

  Future<WriteOutcome?> _runBhpanWrite(
    BhpanMutation request, [
    BhpanWriteStyle style = const BhpanWriteStyle(),
  ]) async {
    final run = widget.onRunWritePrepare,
        confirm = widget.onConfirmWrite,
        cancel = widget.onCancelWrite,
        service = widget.bhpanService;
    if (run == null ||
        confirm == null ||
        cancel == null ||
        service == null ||
        _writeBusy)
      return null;
    final generation = _accountGeneration, policy = widget.routePolicy;
    _setDirectWriteActive(WriteOperation.bhpan);
    try {
      return await runBhpanWriteFlow(
        context: context,
        request: request,
        style: style,
        service: service,
        generation: _bhpanModalScope,
        run: run,
        confirm: confirm,
        cancel: cancel,
        state: () => widget.writeState,
        isCurrent: () =>
            mounted &&
            generation == _accountGeneration &&
            policy == widget.routePolicy &&
            identical(service, widget.bhpanService) &&
            _utilityPage == '北航云盘',
      );
    } finally {
      if (mounted) _setDirectWriteActive(null);
    }
  }

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

  bool get _writeBusy =>
      _directWriteActive != null ||
      _bykcWriteActive != null ||
      _homeSigninActive ||
      widget.writeState.isSubmitting ||
      widget.writeState.intent != null;

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
    if (operation == WriteOperation.bykcDeselectCourse &&
        !await uiConfirmIrreversible(
          context,
          title: '退选这门课程？',
          message: '退选后名额可能被他人选走，无法保证再次选上。',
          action: '确认退选',
          danger: true,
        ))
      return;
    if (!mounted || _writeBusy) return;
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
        failure = attempted ? '结果未确认，请刷新后查看，勿重复提交' : '提交失败，请刷新后重试';
      }
    } finally {
      // 过期或失效的准备结果不能在直接操作结束后变成意外确认页。
      if (mounted &&
          generation == _accountGeneration &&
          intent != null &&
          (outcome == null ||
              widget.writeState.intent?.intentId == intent.intentId) &&
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
            '列表暂未更新，请刷新后查看',
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
    await _runDirectWrite(
      prepare: () => prepare(action),
      failureMessage: action.kind == BykcSignKind.signOut
          ? '签退失败，请刷新后重试'
          : '签到失败，请刷新后重试',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startSigninWrite(SigninPerformAction action) async {
    final prepare = widget.onPrepareSigninWrite;
    if (prepare == null) return;
    await _runDirectWrite(
      prepare: () => prepare(action),
      failureMessage: '签到失败，请刷新后重试',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startCgyyCancelWrite(CgyyCancelAction action) async {
    final prepare = widget.onPrepareCgyyCancelWrite;
    if (prepare == null || _writeBusy) return;
    if (!await uiConfirmCancelReservation(
      context,
      title: '取消这条研讨室预约？',
      message: '取消后时段可能被他人预约，无法恢复。',
    ))
      return;
    await _runDirectWrite(
      prepare: () => prepare(action),
      failureMessage: '取消失败，请刷新后重试',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startLibbookReserveWrite(LibbookReserveAction action) async {
    final prepare = widget.onPrepareLibbookReserveWrite;
    if (prepare == null) return;
    await _runDirectWrite(
      prepare: () => prepare(action),
      failureMessage: '预约失败，请刷新后重试',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startLibbookCancelWrite(LibbookCancelAction action) async {
    final prepare = widget.onPrepareLibbookCancelWrite;
    if (prepare == null || _writeBusy) return;
    if (!await uiConfirmCancelReservation(
      context,
      title: '取消这个座位预约？',
      message: '取消后座位可能被他人预约，无法恢复。',
    ))
      return;
    await _runDirectWrite(
      prepare: () => prepare(action),
      failureMessage: '取消失败，请刷新后重试',
      expectedOperation: action.operation,
    );
  }

  Future<void> _startEvaluation(List<EvaluationSubmitTarget> targets) async {
    final prepare = widget.onPrepareEvaluationWrite;
    if (prepare == null || targets.isEmpty || _writeBusy) return;
    if (!await uiConfirmIrreversible(
      context,
      title: targets.length == 1 ? '提交评教？' : '提交 ${targets.length} 门课程的评教？',
      message: '评教提交后不可修改。',
      action: '确认提交',
    ))
      return;
    await _runDirectWrite(
      prepare: () => prepare(targets),
      failureMessage: '评教失败，请刷新后重试',
      expectedOperation: WriteOperation.evaluationSubmitCourses,
    );
  }

  Future<void> _startYgdkSubmitWrite(YgdkSubmitInput input) async {
    final prepare = widget.onPrepareYgdkSubmitWrite;
    if (!_hasYgdkSubmissionCapabilities || prepare == null) return;
    await _runDirectWrite(
      prepare: () => prepare(input),
      failureMessage: '打卡失败，请重试',
      expectedOperation: WriteOperation.ygdkSubmit,
    );
  }

  Future<void> _startCgyySubmitWrite(CgyySubmitInput input) async {
    final prepare = widget.onPrepareCgyySubmitWrite;
    if (prepare == null) return;
    await _runDirectWrite(
      prepare: () => prepare(input),
      failureMessage: '预约失败，请重试',
      expectedOperation: WriteOperation.cgyySubmitReservation,
    );
  }

  /// 一次点击完成写入：准备后立即提交，不再停留在确认页。
  ///
  /// 一次性意图、过期、冲突和结果不明不重放等保护仍由协调器与 Bridge 负责。
  Future<void> _runDirectWrite({
    required Future<WriteIntent> Function() prepare,
    required String failureMessage,
    required WriteOperation expectedOperation,
  }) async {
    final run = widget.onRunWritePrepare;
    final confirm = widget.onConfirmWrite;
    if (!_hasWriteCommands || run == null || confirm == null || _writeBusy) {
      return;
    }
    final generation = _accountGeneration;
    var attempted = false;
    WriteIntent? intent;
    WriteOutcome? outcome;
    String? failure;
    _setDirectWriteActive(expectedOperation);
    try {
      intent = await run(prepare, expectedOperation: expectedOperation);
      if (mounted && generation == _accountGeneration && intent != null) {
        attempted = true;
        outcome = await confirm();
        if (outcome == null) failure = failureMessage;
      }
    } on Object {
      failure = attempted ? '结果未确认，请刷新后查看，勿重复提交' : failureMessage;
    } finally {
      // 过期等原因未被消费的意图立即释放，避免阻塞下一次操作。
      if (mounted &&
          generation == _accountGeneration &&
          intent != null &&
          (outcome == null ||
              widget.writeState.intent?.intentId == intent.intentId) &&
          !widget.writeState.isSubmitting) {
        await _cancelWrite();
      }
      if (mounted) _setDirectWriteActive(null);
    }
    if (!mounted || generation != _accountGeneration) return;
    if (failure != null) {
      UbaaFeedback.show(context, failure, kind: UbaaFeedbackKind.warning);
    } else if (outcome != null) {
      UbaaFeedback.showOutcome(context, outcome);
    }
  }

  Future<void> _cancelWrite() async {
    final cancel = widget.onCancelWrite;
    if (cancel == null || widget.writeState.isSubmitting) return;
    try {
      await cancel();
    } on Object {
      if (!mounted) return;
      UbaaFeedback.show(context, '操作失败，请重试', kind: UbaaFeedbackKind.error);
    }
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
        UbaaFeedback.show(context, '签到失败，请刷新后重试', kind: UbaaFeedbackKind.error);
      }
      return null;
    } finally {
      if (mounted) _setHomeSigninActive(false);
    }
  }
}
