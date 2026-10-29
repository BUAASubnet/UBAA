import '../shared/feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';
import '../common/section.dart';
import 'cache_settings.dart' show CacheSettings;
import 'profile_details.dart' show ProfileIdentityCard;
import '../common/error_card.dart' show uiShowDiagnosticsDialog;

class ProfileView extends StatelessWidget {
  const ProfileView({
    required this.user,
    required this.routePolicy,
    required this.telemetryEnabled,
    this.telemetryAvailable = true,
    required this.onRoutePolicyChanged,
    required this.onTelemetryChanged,
    required this.onLogout,
    required this.onLogoutAndClearAccount,
    required this.activeRoutes,
    this.onReadDiagnostics,
    this.settingsOnly = false,
    this.onOpenProfile,
    this.onOpenAbout,
    this.cacheAccountId,
    this.canClearBusinessCache = true,
    this.onReadCacheUsage,
    this.onClearBusinessCache,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  final bool settingsOnly;
  final VoidCallback? onOpenProfile, onOpenAbout;
  final String? cacheAccountId;
  final bool canClearBusinessCache;
  final Future<CacheUsageSummary> Function(String)? onReadCacheUsage;
  final Future<CacheClearOutcome> Function(String)? onClearBusinessCache;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final UserSummary? user;
  final RoutePolicy routePolicy;
  final bool telemetryEnabled;
  final bool telemetryAvailable;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final ValueChanged<bool> onTelemetryChanged;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutAndClearAccount;
  final List<ConnectionMode> activeRoutes;
  final String Function()? onReadDiagnostics;

  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.all(
      UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
    ),
    children: [
      if (!settingsOnly) ProfileIdentityCard(user: user),
      if (settingsOnly) ...[
        const UiSectionTitle('个性化'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('外观主题'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  key: const ValueKey('theme-mode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                    ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: onThemeModeChanged == null
                      ? null
                      : (value) => onThemeModeChanged!(value.single),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const UiSectionTitle('连接模式'),
        Card(
          child: Column(
            children: [
              for (final policy in RoutePolicy.values)
                ListTile(
                  key: ValueKey<String>('route-policy-${policy.wireName}'),
                  leading: Icon(switch (policy) {
                    RoutePolicy.auto => Icons.tune,
                    RoutePolicy.direct => Icons.lan_outlined,
                    RoutePolicy.webvpn => Icons.vpn_lock_outlined,
                  }),
                  title: Text(policy.label),
                  subtitle: Text(policy.description),
                  selected: policy == routePolicy,
                  trailing: policy == routePolicy
                      ? const Icon(Icons.check)
                      : null,
                  onTap: policy == routePolicy
                      ? null
                      : () => onRoutePolicyChanged(policy),
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('已认证路线'),
                subtitle: Text(
                  activeRoutes.isEmpty
                      ? '暂无已认证路线'
                      : activeRoutes.map((route) => route.label).join('、'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UiSectionTitle('数据与隐私'),
        if (cacheAccountId != null &&
            onReadCacheUsage != null &&
            onClearBusinessCache != null) ...[
          CacheSettings(
            accountId: cacheAccountId!,
            read: onReadCacheUsage!,
            clear: onClearBusinessCache!,
            enabled: canClearBusinessCache,
          ),
          const SizedBox(height: 8),
        ],
        Card(
          child: Column(
            children: [
              // 未启用统计的版本不显示这个永远灰着的开关。
              if (telemetryAvailable)
                SwitchListTile(
                  secondary: const Icon(Icons.insights_outlined),
                  title: const Text('匿名产品改进统计'),
                  subtitle: const Text('仅统计功能使用次数，不收集账号、成绩或请求内容'),
                  value: telemetryEnabled,
                  onChanged: onTelemetryChanged,
                ),
              if (onReadDiagnostics != null) ...[
                if (telemetryAvailable) const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('本次运行诊断'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      uiShowDiagnosticsDialog(context, onReadDiagnostics!),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UiSectionTitle('账号'),
        if (onOpenProfile != null)
          UiEntryCard(
            title: '我的资料',
            icon: Icons.person_outline,
            onTap: onOpenProfile!,
          ),
        if (onOpenAbout != null) ...[
          const SizedBox(height: 8),
          UiEntryCard(
            title: '关于',
            icon: Icons.info_outline,
            onTap: onOpenAbout!,
          ),
        ],
      ],
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: () => onLogout(),
        icon: const Icon(Icons.logout),
        label: const Text('退出登录'),
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: () => _confirmClearAccount(context),
        icon: const Icon(Icons.delete_outline),
        label: const Text('退出并清除本机账号'),
      ),
    ],
  );

  Future<void> _confirmClearAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除本机账号？'),
        content: const Text(
          '这会退出登录，清除本机账号、保存的密码、缓存、成绩变化记录及提醒设置；学校服务器上的数据不会被删除。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出并清除'),
          ),
        ],
      ),
    );
    // 账号切换或退出已销毁原页面时，旧确认不得清理后来登录的账号。
    if (confirmed == true && context.mounted) {
      // 登录页替换资料页后，根Messenger仍可说明本机文件清理失败。
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        await onLogoutAndClearAccount();
      } on Object {
        if (messenger?.mounted == true) {
          UbaaFeedback.showOn(
            messenger!,
            '本机数据未能完全清除，请稍后重试。',
            kind: UbaaFeedbackKind.error,
          );
        }
      }
    }
  }
}
