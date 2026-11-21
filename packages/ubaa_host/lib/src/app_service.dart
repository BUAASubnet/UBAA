part of 'ubaa_app_host.dart';

const _acceptedPrivacyVersionKey =
    'flutter.ubaa.preferences.accepted_privacy_version';

extension _UbaaAppHostPrivacy on _UbaaAppHostState {
  Future<void> _initializeWithPrivacy() async {
    final version = bundledPrivacyPolicy.version.toString();
    String? accepted;
    try {
      accepted = await _preferences.read(_acceptedPrivacyVersionKey);
    } on Object {
      // 无法确认版本时仍要求用户同意。
    }
    if (_disposed) return;
    if (accepted == version) _allowHostPrivacy();
    unawaited(_attemptAppService(force: true, startup: true));
    unawaited(_controller.refreshAppBootstrap(force: true));
    await _controller.initialize(
      materialRecovery: widget.materialRecovery,
      requestPrivacyAgreement: () async {
        final view = await _controller.refreshAppService();
        await WidgetsBinding.instance.endOfFrame;
        final context = _navigatorKey.currentContext;
        if (_disposed || context == null) return false;
        return uiShowPrivacyAgreement(
          context,
          appServiceAvailable: view.available,
          onAgree: _acceptHostPrivacy,
        );
      },
    );
  }

  void _allowHostPrivacy() {
    _controller.allowHostPrivacy();
    _updateStartup(() => _privacyAccepted = true);
  }

  Future<void> _acceptHostPrivacy() async {
    if (_privacyAccepted) return;
    await _preferences.write(
      _acceptedPrivacyVersionKey,
      bundledPrivacyPolicy.version.toString(),
    );
    if (_disposed) return;
    final view = await _controller.refreshAppService();
    if (_disposed) return;
    if (view.available && view.consent != AppServiceConsent.basic) {
      final state = await _controller.agreePrivacyPolicy();
      if (_disposed) return;
      if (state.consent == AppServiceConsent.agreed &&
          state.telemetryAllowed &&
          !state.telemetryEnabled) {
        await _controller.setProductTelemetryEnabled(true);
      }
    }
    if (_disposed) return;
    _allowHostPrivacy();
    if (!view.available || view.consent == AppServiceConsent.basic) return;
    unawaited(_attemptAppService(force: true, startup: true));
    unawaited(_controller.refreshAppBootstrap(force: true));
  }
}

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
      onTelemetryChanged: _setProductTelemetry,
    );
  }

  AppServiceNotices? get _appServiceNotices {
    final update = _controller.appUpdate;
    if (update == null || !update.gateActive) return null;
    return AppServiceNotices(
      update: update,
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
    if (_disposed || _updatePromptOpen || _appServicePopupOpen) return;
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
      _syncAppServicePopup();
    }
  }

  static const _updateReminderKey = 'flutter.ubaa.update_reminder';

  Future<void> _loadUpdateReminder() async {
    try {
      final saved = await _preferences.read(_updateReminderKey);
      final parts = saved?.split('\n');
      if (parts != null && parts.length == 2) {
        _snoozedUpdateVersion = parts[0];
        _updateReminderAt = DateTime.tryParse(parts[1]);
      }
    } on Object {
      // 普通偏好读取失败时仍允许显示更新提示。
    }
    if (_disposed) return;
    _updateReminderLoaded = true;
    _scheduleUpdateReminder();
    _syncAppServicePopup();
  }

  void _scheduleUpdateReminder() {
    _updateReminderTimer?.cancel();
    final at = _updateReminderAt;
    if (_disposed || at == null || !DateTime.now().isBefore(at)) return;
    _updateReminderTimer = Timer(
      at.difference(DateTime.now()),
      _syncAppServicePopup,
    );
  }

  Future<void> _snoozeUpdate(String version) async {
    _snoozedUpdateVersion = version;
    _updateReminderAt = DateTime.now().add(const Duration(hours: 1));
    _scheduleUpdateReminder();
    try {
      await _preferences.write(
        _updateReminderKey,
        '$version\n${_updateReminderAt!.toIso8601String()}',
      );
    } on Object {
      // 保存失败时，本次运行仍保持一小时的提醒间隔。
    }
  }

  /// 新版本优先，公告逐条显示，更新关闭后一小时再提醒，公告确认后保存已读状态。
  void _syncAppServicePopup() {
    if (_disposed ||
        _readyController == null ||
        !_updateReminderLoaded ||
        _wasBackgrounded ||
        _appServicePopupOpen ||
        _updatePromptOpen)
      return;
    final update = _controller.appUpdate;
    final version = update?.latestVersion;
    final showUpdate =
        update != null &&
        !update.gateActive &&
        update.status == AppUpdateStatus.updateAvailable &&
        version != null &&
        !(version == _snoozedUpdateVersion &&
            _updateReminderAt != null &&
            DateTime.now().isBefore(_updateReminderAt!));
    final next = _controller.pendingAnnouncements.firstOrNull;
    if (!showUpdate && next == null) return;
    _appServicePopupOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      var continueQueue = false;
      try {
        final context = _navigatorKey.currentContext;
        if (_disposed || context == null || !context.mounted) return;
        if (showUpdate) {
          final current = _controller.appUpdate;
          if (current?.latestVersion != version ||
              current?.status != AppUpdateStatus.updateAvailable ||
              current!.gateActive) {
            continueQueue = true;
            return;
          }
          final go = await uiShowReleaseNotes(
            context,
            version: version,
            notes: current.releaseNotes,
            canUpdate: current.url != null,
          );
          if (_disposed) return;
          await _snoozeUpdate(version);
          if (go && current.url != null) await _openAppServiceUrl(current.url!);
          continueQueue = true;
        } else if (next != null) {
          // 帧间状态可能已经变化，只显示仍然未读且有效的公告。
          if (!_controller.pendingAnnouncements.any((a) => a.id == next.id)) {
            continueQueue = true;
            return;
          }
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
            continueQueue = !_controller.pendingAnnouncements.any(
              (a) => a.id == next.id,
            );
          }
        }
      } finally {
        _appServicePopupOpen = false;
        if (!_disposed && continueQueue) _syncAppServicePopup();
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}
