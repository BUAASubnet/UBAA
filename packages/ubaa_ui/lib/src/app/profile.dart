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
          child: _setting(
            context,
            icon: Icons.palette_outlined,
            title: '外观主题',
            subtitle: '仅本次生效，重启后跟随系统',
            control: DropdownButton<ThemeMode>(
              isExpanded: true,
              value: themeMode,
              onChanged: onThemeModeChanged == null
                  ? null
                  : (value) {
                      if (value != null) onThemeModeChanged!(value);
                    },
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const UiSectionTitle('连接'),
        Card(
          child: Column(
            children: [
              _setting(
                context,
                icon: Icons.tune,
                title: '连接模式',
                control: DropdownButton<RoutePolicy>(
                  isExpanded: true,
                  value: routePolicy,
                  onChanged: (value) {
                    if (value != null) onRoutePolicyChanged(value);
                  },
                  items: RoutePolicy.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                ),
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
              SwitchListTile(
                secondary: const Icon(Icons.insights_outlined),
                title: const Text('匿名产品改进统计'),
                subtitle: Text(
                  telemetryAvailable ? '仅统计功能使用次数，不收集账号、成绩或请求内容' : '此版本未启用统计功能',
                ),
                value: telemetryEnabled,
                onChanged: telemetryAvailable ? onTelemetryChanged : null,
              ),
              if (onReadDiagnostics != null) ...[
                const Divider(height: 1),
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

  Widget _setting(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget control,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 480 ||
          MediaQuery.textScalerOf(context).scale(14) > 20;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (stacked) ...[const SizedBox(height: 8), control],
                ],
              ),
            ),
            if (!stacked) ...[
              const SizedBox(width: 16),
              SizedBox(width: 220, child: control),
            ],
          ],
        ),
      );
    },
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
          messenger!.showSnackBar(
            const SnackBar(content: Text('本机数据未能完全清除，请稍后重试。')),
          );
        }
      }
    }
  }
}
