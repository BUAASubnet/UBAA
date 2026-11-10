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

  /// 首启或政策升版后弹出一次选择；状态在别处改变后撤下已经过时的弹窗。
  void _syncConsentPrompt() {
    if (_disposed || _readyController == null) return;
    if (!_controller.appService.needsConsentPrompt) {
      final route = _consentRoute;
      if (route != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (route.isActive) route.navigator?.removeRoute(route);
        });
      }
      return;
    }
    if (_consentRoute != null || _consentScheduled) return;
    _consentScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _consentScheduled = false;
      if (_disposed ||
          _consentRoute != null ||
          !_controller.appService.needsConsentPrompt)
        return;
      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        // 首帧前导航尚未建立，下一帧再试。
        _syncConsentPrompt();
        return;
      }
      final route = uiPrivacyConsentRoute(
        navigator.context,
        policy: _controller.privacyPolicy,
        view: _controller.appService,
        onAgree: _agreePrivacy,
        onDecline: _declinePrivacy,
      );
      _consentRoute = route;
      unawaited(
        navigator.push(route).whenComplete(() {
          if (identical(_consentRoute, route)) _consentRoute = null;
        }),
      );
    });
  }
}
