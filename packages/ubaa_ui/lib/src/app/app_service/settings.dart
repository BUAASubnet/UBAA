import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/dialogs/confirmation.dart' show uiConfirmIrreversible;
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
    required this.onWithdraw,
    required this.onTelemetryChanged,
    required this.onErase,
  });
  final AppServiceView view;
  final PrivacyPolicyDocument policy;
  final Future<void> Function() onAgree, onDecline, onWithdraw;
  final Future<void> Function(bool enabled) onTelemetryChanged;
  final Future<AppServiceEraseOutcome> Function() onErase;
}

/// 设置页「数据与隐私」卡片中的应用服务条目：政策、同意、统计开关与删除。
class AppServiceSettings extends StatelessWidget {
  const AppServiceSettings({super.key, required this.controls});
  final AppServiceControls controls;

  AppServiceView get _view => controls.view;
  bool get _agreed => _view.consent == AppServiceConsent.agreed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final erasing = _view.erase == AppServiceEraseStatus.running;
    final telemetryUsable = _agreed && _view.telemetryAllowed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          key: const ValueKey('settings-privacy-policy'),
          leading: const Icon(Icons.policy_outlined),
          title: const Text('隐私政策'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => uiShowPrivacyPolicy(context, controls.policy),
        ),
        const Divider(height: 1),
        _consentTile(context),
        const Divider(height: 1),
        SwitchListTile(
          key: const ValueKey('settings-product-telemetry'),
          secondary: const Icon(Icons.insights_outlined),
          title: const Text('产品改进统计'),
          subtitle: Text(
            !_view.telemetryAllowed
                ? '当前运行环境已关闭统计'
                : _agreed
                ? '按天汇总功能使用、错误类别和加载耗时，按分钟汇总登录与加载次数，不含密码、成绩、课表等内容'
                : '同意隐私政策后可用',
          ),
          // 基础模式或硬关闭时显示为关闭，不能让保存值误报统计正在进行。
          value: telemetryUsable && _view.telemetryEnabled,
          onChanged: telemetryUsable && !erasing
              ? (value) => unawaited(_setTelemetry(context, value))
              : null,
        ),
        if (_view.canErase) ...[
          const Divider(height: 1),
          ListTile(
            key: const ValueKey('settings-erase-telemetry'),
            enabled: !erasing,
            leading: Icon(
              Icons.delete_sweep_outlined,
              color: erasing ? null : colors.error,
            ),
            title: Text(
              '删除已上传的统计数据',
              style: TextStyle(color: erasing ? null : colors.error),
            ),
            subtitle: switch (_view.erase) {
              AppServiceEraseStatus.running => const Text('正在删除…'),
              AppServiceEraseStatus.pending => const Text(
                '删除尚未完成，联网后会自动重试，也可以点按立即重试',
              ),
              AppServiceEraseStatus.idle => null,
            },
            trailing: erasing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: () => unawaited(_erase(context)),
          ),
        ],
      ],
    );
  }

  Widget _consentTile(BuildContext context) {
    final (title, subtitle, action) = switch (_view.consent) {
      AppServiceConsent.agreed => ('已同意隐私政策', '可以检查更新、接收公告，并按开关上传统计', '撤回'),
      AppServiceConsent.reconsentRequired => (
        '隐私政策已更新',
        '同意新版政策后恢复检查更新、公告和统计',
        '查看',
      ),
      AppServiceConsent.basic || AppServiceConsent.unasked => (
        '未同意隐私政策',
        '基础模式：不检查更新、不接收公告、不上传统计，学校功能照常可用',
        '同意',
      ),
    };
    return ListTile(
      key: const ValueKey('settings-privacy-consent'),
      leading: const Icon(Icons.verified_user_outlined),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: _agreed
          ? TextButton(
              key: const ValueKey('settings-privacy-withdraw'),
              onPressed: () => unawaited(_withdraw(context)),
              child: Text(action),
            )
          : FilledButton.tonal(
              key: const ValueKey('settings-privacy-agree'),
              onPressed: () => uiShowPrivacyConsent(
                context,
                policy: controls.policy,
                view: _view,
                onAgree: controls.onAgree,
                onDecline: controls.onDecline,
              ),
              child: Text(action),
            ),
    );
  }

  Future<void> _setTelemetry(BuildContext context, bool value) async {
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

  Future<void> _withdraw(BuildContext context) async {
    final confirmed = await uiConfirmIrreversible(
      context,
      title: '撤回同意？',
      message:
          '撤回后，应用不再检查更新、接收公告或上传统计，尚未上传的统计会被清除。'
          '已经上传的数据不会自动删除，可以使用「删除已上传的统计数据」。学校功能不受影响。',
      action: '撤回',
    );
    if (!confirmed || !context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await controls.onWithdraw();
    } on Object {
      if (messenger != null) {
        UbaaFeedback.showOn(
          messenger,
          '未能撤回，请重试',
          kind: UbaaFeedbackKind.error,
        );
      }
    }
  }

  Future<void> _erase(BuildContext context) async {
    // 删除标记仍在时只是重试同一次删除，不再重复确认。
    if (_view.erase != AppServiceEraseStatus.pending) {
      final confirmed = await uiConfirmIrreversible(
        context,
        title: '删除已上传的统计数据？',
        message:
            '服务器会删除本机已上传的统计明细，本机随后改用新的统计标识。'
            '已经汇总、不含任何标识的整体数字会保留。统计开关保持不变。',
        action: '删除',
        danger: true,
      );
      if (!confirmed || !context.mounted) return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    AppServiceEraseOutcome outcome;
    try {
      outcome = await controls.onErase();
    } on Object {
      outcome = AppServiceEraseOutcome.pending;
    }
    if (messenger == null) return;
    final (message, kind) = switch (outcome) {
      AppServiceEraseOutcome.succeeded => (
        '已删除已上传的统计数据',
        UbaaFeedbackKind.success,
      ),
      AppServiceEraseOutcome.pending => (
        '暂时无法连接统计服务，删除会在稍后自动重试',
        UbaaFeedbackKind.warning,
      ),
      AppServiceEraseOutcome.unavailable => (
        '本机没有可删除的统计数据',
        UbaaFeedbackKind.info,
      ),
    };
    UbaaFeedback.showOn(messenger, message, kind: kind);
  }
}
