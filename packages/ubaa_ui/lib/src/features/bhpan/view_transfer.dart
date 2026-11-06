part of 'view.dart';

/// 上传与下载：共用传输卡片，账号或位置变化后旧任务不得继续交付。
extension _BhpanTransfers on _BhpanViewState {
  Future<void> Function() _track(
    BhpanTransferTask transfer, {
    required String label,
    required bool upload,
  }) {
    _transfer = transfer;
    _progressHide?.cancel();
    _update(() {
      _progressLabel = label;
      _progressUpload = upload;
      _progress = const BhpanTransferProgress(
        phase: BhpanTransferPhase.queued,
        bytes: 0,
        total: 0,
      );
    });
    Future<void> update() async {
      try {
        final progress = await transfer.progress();
        if (mounted && identical(_transfer, transfer))
          _update(() => _progress = progress);
      } on Object catch (error) {
        transfer.cancel();
        if (mounted && identical(_transfer, transfer))
          _notify(_message(error), UbaaFeedbackKind.error);
      }
    }

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => unawaited(update()),
    );
    return update;
  }

  /// 传输结束后停止轮询；完成或取消的卡片稍后自动收起，失败与待核对保留。
  void _finishTrack(BhpanTransferTask? task) {
    if (!identical(_transfer, task)) return;
    _progressTimer?.cancel();
    _progressTimer = null;
    final phase = _progress?.phase;
    if (phase == BhpanTransferPhase.completed ||
        phase == BhpanTransferPhase.cancelled) {
      _progressHide?.cancel();
      _progressHide = Timer(const Duration(seconds: 3), () {
        if (identical(_transfer, task)) _update(() => _progress = null);
      });
    }
  }

  /// 上传文件：个人文档库先试秒传；云端没有相同文件时再准备普通上传，
  /// 普通上传的确认框就是「要不要完整上传」的询问。
  Future<void> _upload() async {
    final service = _service, pick = widget.access.pickFile;
    if (service == null ||
        pick == null ||
        _trail.isEmpty ||
        !_trail.last.isFolder ||
        _trail.last.scope == BhpanScope.recycle)
      return;
    final generation = _generation, parent = _trail.last;
    BhpanTransferTask? task;
    BhpanLocalFile? selected;
    Future<void> Function()? refresh;
    try {
      final source = await pick();
      selected = source;
      if (!_current(generation) || source == null) return;
      var note = '上传到「${parent.name}」。';
      if (_tryFastUpload) {
        final fast = service.createTransfer();
        task = fast;
        refresh = _track(fast, label: source.name, upload: true);
        try {
          final result = await _mutate(
            BhpanMutation(
              BhpanMutationKind.uploadFast,
              target: parent.handle,
              source: source,
              transfer: fast,
            ),
            const BhpanWriteStyle(),
            true,
          );
          await refresh();
          // 用户在秒传确认框取消，或秒传已有结果，都不再继续。
          if (result != null ||
              (await fast.progress()).phase != BhpanTransferPhase.blocked)
            return;
        } on Object catch (error) {
          await refresh();
          final phase = (await fast.progress()).phase;
          if (phase != BhpanTransferPhase.blocked) {
            if (_current(generation))
              _notify(_message(error), UbaaFeedbackKind.error);
            return;
          }
        } finally {
          fast.cancel();
        }
        if (!_current(generation)) return;
        note = '云端没有相同的文件，需要完整上传文件内容到「${parent.name}」。';
      }
      final transfer = service.createTransfer();
      task = transfer;
      // 同一个控制柄贯穿准备、确认和提交。
      refresh = _track(transfer, label: source.name, upload: true);
      await _mutate(
        BhpanMutation(
          BhpanMutationKind.upload,
          target: parent.handle,
          source: source,
          transfer: transfer,
        ),
        BhpanWriteStyle(note: note),
      );
      await refresh();
    } on Object catch (error) {
      if (mounted && identical(service, _service))
        _notify(_message(error), UbaaFeedbackKind.error);
    } finally {
      try {
        await selected?.release();
      } on Object catch (error) {
        if (_current(generation))
          _notify(_message(error), UbaaFeedbackKind.error);
      }
      task?.cancel();
      await refresh?.call();
      if (identical(_transfer, task) &&
          _progress?.phase == BhpanTransferPhase.awaitingConfirmation)
        _update(() => _progress = null);
      _finishTrack(task);
    }
  }

  /// [preview] 为 true 时下载到宿主给出的临时位置并调起系统预览。
  Future<void> _download(List<BhpanItem> items, {bool preview = false}) async {
    final service = _service,
        pick = preview ? widget.access.previewFile : widget.access.pickDownload;
    if (service == null ||
        pick == null ||
        items.isEmpty ||
        _working ||
        _loading)
      return;
    final generation = _generation, activity = Object();
    final base = items.length == 1
        ? items.single.name.replaceAll(RegExp(r'[\\/\r\n]'), '_')
        : '北航云盘下载';
    final batch = items.length != 1 || items.single.isFolder;
    final name = base.trim().isEmpty ? '北航云盘下载' : base;
    final suggested = batch ? '$name.zip' : name;
    BhpanDownloadDestination? destination;
    BhpanTransferTask? task;
    Future<void> Function()? refresh;
    _update(() {
      _working = true;
      _mutationActivity = activity;
    });
    try {
      destination = await pick(
        suggested,
        () => _current(generation) && identical(service, _service),
      );
      if (destination == null || !_current(generation)) return;
      final transfer = service.createTransfer();
      task = transfer;
      refresh = _track(
        transfer,
        label: preview ? '正在打开 $suggested' : suggested,
        upload: false,
      );
      final receipt = await service.download(
        items.map((item) => item.handle).toList(),
        name,
        destination.path,
        destination.overwrite,
        transfer,
      );
      if (!_current(generation)) return;
      await destination.deliver(
        () => _current(generation) && identical(service, _service),
      );
      await refresh();
      if (_current(generation)) {
        if (!preview)
          _notify(
            '已保存 $suggested（${bhpanBytes(receipt.bytes)}）',
            UbaaFeedbackKind.success,
          );
        _update(
          () => _progress = BhpanTransferProgress(
            phase: BhpanTransferPhase.completed,
            bytes: receipt.bytes,
            total: receipt.bytes,
          ),
        );
      }
    } on Object catch (error) {
      if (_current(generation))
        _notify(_message(error), UbaaFeedbackKind.error);
    } finally {
      task?.cancel();
      if (identical(_transfer, task) &&
          _progress?.phase != BhpanTransferPhase.completed)
        await refresh?.call();
      _finishTrack(task);
      try {
        await destination?.discard();
      } on Object catch (error) {
        if (_current(generation))
          _notify(_message(error), UbaaFeedbackKind.error);
      }
      if (mounted && identical(_mutationActivity, activity))
        _update(() {
          _working = false;
          _mutationActivity = null;
        });
    }
  }
}
