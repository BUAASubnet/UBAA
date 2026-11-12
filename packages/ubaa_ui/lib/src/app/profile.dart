import '../shared/feedback.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/theme.dart';
import '../common/section.dart';
import 'app_service/settings.dart' show AppServiceControls, AppServiceSettings;
import 'cache_settings.dart' show CacheSettings;
import 'profile_details.dart' show ProfileIdentityCard;
import '../common/error_card.dart' show uiShowDiagnosticsDialog;
import '../shared/dialogs/confirmation.dart' show uiConfirmIrreversible;

class ProfileView extends StatelessWidget {
  const ProfileView({
    required this.user,
    required this.routePolicy,
    this.appService,
    required this.onRoutePolicyChanged,
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

  /// 构建接入应用服务时由宿主提供；为 null 时不显示隐私与统计条目。
  final AppServiceControls? appService;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutAndClearAccount;
  final List<ConnectionMode> activeRoutes;
  final String Function()? onReadDiagnostics;

  bool get hasCache =>
      cacheAccountId != null &&
      onReadCacheUsage != null &&
      onClearBusinessCache != null;

  @override
  Widget build(BuildContext context) => ListView(
    padding: UbaaTheme.pageInsets(context, top: 8),
    children: [
      if (!settingsOnly) ProfileIdentityCard(user: user),
      if (settingsOnly) ...[
        const UiSectionTitle('个性化'),
        Card(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final picker = SegmentedButton<ThemeMode>(
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
              );
              // 宽屏把选择放在行尾，不把三个选项拉成整行宽。
              final inline =
                  constraints.maxWidth >=
                  MediaQuery.textScalerOf(context).scale(600);
              return ListTile(
                leading: const Icon(Icons.palette_outlined),
                title: const Text('外观主题'),
                trailing: inline
                    ? SizedBox(
                        width: MediaQuery.textScalerOf(context).scale(300),
                        child: picker,
                      )
                    : null,
                subtitle: inline
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(width: double.infinity, child: picker),
                      ),
              );
            },
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
                    RoutePolicy.auto => Icons.auto_mode,
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
              // 当前状态说明，不是可选项：小字、无点按反馈；未连接时不显示。
              if (activeRoutes.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前连接：${activeRoutes.map((route) => route.label).join('、')}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const UiSectionTitle('数据与隐私'),
        // 缓存、统计与诊断合在一张卡片里，与「连接模式」「账号」的分组方式一致。
        Card(
          child: Column(
            children: [
              if (hasCache)
                CacheSettings(
                  accountId: cacheAccountId!,
                  read: onReadCacheUsage!,
                  clear: onClearBusinessCache!,
                  enabled: canClearBusinessCache,
                  inCard: false,
                ),
              // 未接入应用服务的构建不显示统计开关。
              if (appService case final controls?) ...[
                if (hasCache) const Divider(height: 1),
                AppServiceSettings(controls: controls),
              ],
              if (onReadDiagnostics != null) ...[
                if (hasCache || appService != null) const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('诊断信息'),
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
        Card(
          child: Column(
            children: [
              ListTile(
                key: const ValueKey('settings-logout'),
                leading: const Icon(Icons.logout),
                title: const Text('退出登录'),
                onTap: () => unawaited(onLogout()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '退出并清除本机数据',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => _confirmClearAccount(context),
              ),
            ],
          ),
        ),
      ],
    ],
  );

  Future<void> _confirmClearAccount(BuildContext context) async {
    final confirmed = await uiConfirmIrreversible(
      context,
      title: '退出并清除数据？',
      message:
          '这会退出登录，清除保存的密码、已保存的学校数据、成绩变化记录及提醒设置。本机日程和账号关联会保留，学校服务器上的数据不会被删除。',
      action: '退出并清除',
      danger: true,
    );
    // 账号切换或退出已销毁原页面时，旧确认不得清理后来登录的账号。
    if (confirmed && context.mounted) {
      // 登录页替换资料页后，根Messenger仍可说明本机文件清理失败。
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        await onLogoutAndClearAccount();
      } on Object {
        if (messenger?.mounted == true) {
          UbaaFeedback.showOn(
            messenger!,
            '部分本机数据未清除，请重试',
            kind: UbaaFeedbackKind.error,
          );
        }
      }
    }
  }
}
