part of '../widgets.dart';

class _ProfileView extends StatelessWidget {
  const _ProfileView({
    required this.user,
    required this.routePolicy,
    required this.telemetryEnabled,
    required this.onRoutePolicyChanged,
    required this.onTelemetryChanged,
    required this.onLogout,
    required this.onLogoutAndClearAccount,
    required this.activeRoutes,
    this.onReadDiagnostics,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final UserSummary? user;
  final RoutePolicy routePolicy;
  final bool telemetryEnabled;
  final ValueChanged<RoutePolicy> onRoutePolicyChanged;
  final ValueChanged<bool> onTelemetryChanged;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutAndClearAccount;
  final List<ConnectionMode> activeRoutes;
  final String Function()? onReadDiagnostics;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        padding: EdgeInsets.all(
          UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
        ),
        children: <Widget>[
          _ProfileIdentityCard(user: user),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('外观主题'),
              subtitle: const Text('本次运行生效，重启后跟随系统'),
              trailing: DropdownButton<ThemeMode>(
                value: themeMode,
                onChanged: onThemeModeChanged == null
                    ? null
                    : (value) {
                        if (value != null) onThemeModeChanged!(value);
                      },
                items: const [
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text('跟随系统'),
                  ),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.tune),
                  title: const Text('连接模式'),
                  subtitle: Text(routePolicy.description),
                  trailing: DropdownButton<RoutePolicy>(
                    value: routePolicy,
                    onChanged: (value) {
                      if (value != null) onRoutePolicyChanged(value);
                    },
                    items: RoutePolicy.values
                        .map(
                          (item) => DropdownMenuItem<RoutePolicy>(
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
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.insights_outlined),
                  title: const Text('匿名产品改进统计'),
                  subtitle: const Text('仅统计功能使用次数，不收集账号、成绩或请求内容'),
                  value: telemetryEnabled,
                  onChanged: onTelemetryChanged,
                ),
                if (onReadDiagnostics != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.bug_report_outlined),
                    title: const Text('本次运行诊断'),
                    subtitle: const Text('查看或复制错误信息，不会自动上传'),
                    onTap: () =>
                        _showDiagnosticsDialog(context, onReadDiagnostics!),
                  ),
                ],
              ],
            ),
          ),
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
          const SizedBox(height: 32),
          Text(
            'UBAA 应用\nMake BUAA Great Again',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );

  Future<void> _confirmClearAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除本机账号？'),
        content: const Text('这会退出登录，并删除你主动保存的账号密码；学校服务器上的数据不会被删除。'),
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
      await onLogoutAndClearAccount();
    }
  }
}
