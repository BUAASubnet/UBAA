part of 'ubaa_app_host.dart';

/// 应用服务的隐私选择与设置接线。
///
/// 控制器操作不抛错，返回 Core 实际保存的状态；这里把“没有达到预期状态”
/// 转成异常，让界面提示重试，而不是把选择当作已经生效。
extension _UbaaAppHostAppService on _UbaaAppHostState {
  Future<void> _agreePrivacy() async {
    final view = await _controller.agreePrivacyPolicy();
    if (view.consent != AppServiceConsent.agreed) {
      throw StateError('同意未保存');
    }
  }

  Future<void> _declinePrivacy() async {
    final view = await _controller.declinePrivacyPolicy();
    if (view.consent != AppServiceConsent.basic) {
      throw StateError('选择未保存');
    }
  }

  Future<void> _withdrawPrivacy() async {
    final view = await _controller.withdrawPrivacyConsent();
    if (view.consent != AppServiceConsent.basic) {
      throw StateError('撤回未保存');
    }
  }

  Future<void> _setProductTelemetry(bool enabled) async {
    final view = await _controller.setProductTelemetryEnabled(enabled);
    if (view.telemetryEnabled != enabled) throw StateError('开关未保存');
  }

  AppServiceControls? get _appServiceControls {
    final view = _controller.appService;
    if (!view.available) return null;
    return AppServiceControls(
      view: view,
      policy: _controller.privacyPolicy,
      onAgree: _agreePrivacy,
      onDecline: _declinePrivacy,
      onWithdraw: _withdrawPrivacy,
      onTelemetryChanged: _setProductTelemetry,
      onErase: _controller.eraseUploadedTelemetry,
    );
  }

  AppServiceNotices? get _appServiceNotices {
    final update = _controller.appUpdate;
    final banners = [
      for (final announcement in _controller.pendingAnnouncements)
        if (announcement.level == AppAnnouncementLevel.banner) announcement,
    ];
    if (update == null && banners.isEmpty) return null;
    return AppServiceNotices(
      update: update,
      banners: banners,
      onOpenUrl: _openAppServiceUrl,
      onDismissUpdate: _controller.dismissUpdateAvailable,
      onDismissAnnouncement: _controller.markAnnouncementRead,
    );
  }

  Future<void> _openAppServiceUrl(Uri url) async {
    var opened = false;
    try {
      opened = await widget.openExternalUrl(url);
    } on Object {
      opened = false;
    }
    if (opened || _disposed) return;
    if (_messengerKey.currentState case final messenger?) {
      UbaaFeedback.showOn(
        messenger,
        '未能打开浏览器，请稍后重试',
        kind: UbaaFeedbackKind.error,
      );
    }
  }

  /// 用户主动访问学校被门控拒绝时提示更新；自动任务不会发出这个信号。
  Future<void> _showUpdatePrompt() async {
    if (_disposed || _updatePromptOpen) return;
    _updatePromptOpen = true;
    try {
      // 链接与门控以共享存储为准，另一进程可能刚刚刷新过配置。
      await _controller.refreshAppService();
      final context = _navigatorKey.currentContext;
      if (_disposed || context == null || !context.mounted) return;
      final url = _controller.appUpdate?.url;
      final update = await uiShowUpdateRequired(
        context,
        canUpdate: url != null,
      );
      if (update && url != null) await _openAppServiceUrl(url);
    } finally {
      _updatePromptOpen = false;
    }
  }

  /// 弹窗级公告逐条显示；确认后记为已读，再显示下一条。
  void _syncAnnouncementPopup() {
    if (_disposed || _readyController == null || _announcementOpen) return;
    final next = _controller.pendingAnnouncements
        .where((item) => item.level == AppAnnouncementLevel.popup)
        .firstOrNull;
    if (next == null) return;
    _announcementOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final context = _navigatorKey.currentContext;
        if (_disposed || context == null || !context.mounted) return;
        // 帧间状态可能已经变化，确认这条公告仍然待显示。
        if (!_controller.pendingAnnouncements.any((a) => a.id == next.id))
          return;
        final link = next.linkUrl;
        final confirmed = await uiShowAnnouncement(
          context,
          next,
          onOpenLink: link == null
              ? null
              : () => unawaited(_openAppServiceUrl(link)),
        );
        if (confirmed && !_disposed) {
          await _controller.markAnnouncementRead(next.id);
        }
      } finally {
        _announcementOpen = false;
        if (!_disposed) _syncAnnouncementPopup();
      }
    });
  }
}
