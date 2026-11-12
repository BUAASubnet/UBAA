import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/feedback.dart';
import 'privacy.dart';

/// 设置页应用服务条目需要的状态与操作，由宿主从控制器装配。
///
/// 各操作完成时控制器已经持久化结果；失败时抛出，界面只提示，不自行改动状态。
final class AppServiceControls {
  const AppServiceControls({
    required this.view,
    required this.policy,
    required this.onAgree,
    required this.onDecline,
    required this.onTelemetryChanged,
  });
  final AppServiceView view;
  final PrivacyPolicyDocument policy;
  final Future<void> Function() onAgree, onDecline;
  final Future<void> Function(bool enabled) onTelemetryChanged;
}

/// 设置页的产品改进统计开关。
class AppServiceSettings extends StatelessWidget {
  const AppServiceSettings({super.key, required this.controls});
  final AppServiceControls controls;

  AppServiceView get _view => controls.view;
  bool get _agreed => _view.consent == AppServiceConsent.agreed;

  @override
  Widget build(BuildContext context) {
    final erasing = _view.erase == AppServiceEraseStatus.running;
    return SwitchListTile(
      key: const ValueKey('settings-product-telemetry'),
      secondary: const Icon(Icons.insights_outlined),
      title: const Text('产品改进统计'),
      subtitle: const Text('是否参与匿名统计以帮助改进产品'),
      // 旧版基础模式仍显示为关闭，用户可以通过开关主动重新启用。
      value: _agreed && _view.telemetryAllowed && _view.telemetryEnabled,
      onChanged: _view.telemetryAllowed && !erasing
          ? (value) => unawaited(_setTelemetry(context, value))
          : null,
    );
  }

  Future<void> _setTelemetry(BuildContext context, bool value) async {
    if (value && !_agreed) {
      await uiShowPrivacyConsent(
        context,
        policy: controls.policy,
        view: _view,
        onAgree: () async {
          await controls.onAgree();
          await controls.onTelemetryChanged(true);
        },
        onDecline: controls.onDecline,
      );
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await controls.onTelemetryChanged(value);
    } on Object {
      if (messenger != null) {
        UbaaFeedback.showOn(
          messenger,
          '统计设置未能保存，请重试',
          kind: UbaaFeedbackKind.error,
        );
      }
    }
  }
}
