part of 'shell.dart';

/// 自适应导航的展示；页面与写入状态由 Shell 持有。
extension UbaaShellNavigation on _UbaaMainShellState {
  Widget _buildRail(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(
      // 导航只在内容溢出时滚动，边界不随触摸板回弹。
      physics: const ClampingScrollPhysics(),
    ),
    child: _buildRailContent(context),
  );

  Widget _buildRailContent(BuildContext context) {
    final extended = MediaQuery.sizeOf(context).width >= 1000;
    final colors = Theme.of(context).colorScheme;
    if (!extended) {
      return NavigationRail(
        scrollable: true,
        minWidth: 88,
        selectedIndex: _selectedIndex < 4 && _utilityPage == null
            ? _selectedIndex
            : null,
        onDestinationSelected: _selectTab,
        labelType: NavigationRailLabelType.none,
        leading: _buildRailLeading(context, false),
        trailingAtBottom: true,
        trailing: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '设置',
                isSelected:
                    _selectedIndex == UiDestination.settings.index &&
                    _utilityPage == null,
                style: IconButton.styleFrom(minimumSize: const Size(56, 48))
                    .copyWith(
                      backgroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? colors.secondaryContainer
                            : null,
                      ),
                      foregroundColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? colors.onSecondaryContainer
                            : null,
                      ),
                    ),
                onPressed: () => _selectTab(UiDestination.settings.index),
                icon: Icon(UiDestination.settings.icon),
                selectedIcon: Icon(UiDestination.settings.selectedIcon),
              ),
              const SizedBox(height: 8),
              IconButton(
                tooltip: '关于',
                onPressed: () => _openUtility('关于'),
                icon: const Icon(Icons.info_outline),
              ),
              const SizedBox(height: 8),
              IconButton(
                tooltip: '退出登录',
                color: colors.error,
                onPressed: _logout,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
        ),
        destinations: _UbaaMainShellState._tabs
            .take(4)
            .map(
              (tab) => NavigationRailDestination(
                padding: const EdgeInsets.symmetric(vertical: 8),
                icon: Tooltip(
                  message: tab.label,
                  excludeFromSemantics: true,
                  child: Icon(tab.icon),
                ),
                selectedIcon: Tooltip(
                  message: tab.label,
                  excludeFromSemantics: true,
                  child: Icon(tab.selectedIcon),
                ),
                label: Text(tab.label),
              ),
            )
            .toList(),
      );
    }
    Widget entry(UiDestination tab) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ListTile(
        selected: _selectedIndex == tab.index && _utilityPage == null,
        selectedTileColor: colors.secondaryContainer,
        selectedColor: colors.onSecondaryContainer,
        leading: Icon(
          _selectedIndex == tab.index ? tab.selectedIcon : tab.icon,
        ),
        title: Text(tab.label),
        onTap: () => _selectTab(tab.index),
      ),
    );
    return Material(
      color: colors.surfaceContainer,
      child: SizedBox(
        width: 248,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: _buildRailLeading(context, true),
              ),
              Expanded(
                child: ListView(
                  primary: false,
                  children: [
                    for (final tab in _UbaaMainShellState._tabs.take(4))
                      entry(tab),
                  ],
                ),
              ),
              entry(UiDestination.settings),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  onTap: () => _openUtility('关于'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: ListTile(
                  iconColor: colors.error,
                  textColor: colors.error,
                  leading: const Icon(Icons.logout),
                  title: const Text('退出登录'),
                  onTap: _logout,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRailLeading(
    BuildContext context,
    bool extended, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final iconWidget = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/icons/app_icon.png',
        package: 'ubaa_ui',
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => CircleAvatar(
          radius: 18,
          child: Text((widget.user?.preferredName ?? 'U').characters.first),
        ),
      ),
    );

    final name = widget.user?.preferredName ?? '用户';
    final username = widget.user?.username ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap ?? () => _openUtility('我的资料'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: extended
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconWidget,
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (username.isNotEmpty && username != name) ...[
                          const SizedBox(height: 2),
                          Text(
                            username,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              )
            : iconWidget,
      ),
    );
  }

  Drawer _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = widget.user?.preferredName ?? 'UBAA';
    final username = widget.user?.username ?? '';
    void open(BuildContext drawerContext, String page) {
      Navigator.of(drawerContext).pop();
      _openUtility(page);
    }

    return Drawer(
      child: SafeArea(
        child: Builder(
          builder: (drawerContext) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 头部卡片：左边应用图标，右边姓名与学号；点按进入我的资料。
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Material(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => open(drawerContext, '我的资料'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.asset(
                              'assets/icons/app_icon.png',
                              package: 'ubaa_ui',
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                radius: 26,
                                child: Text(name.characters.first),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                ),
                                if (username.isNotEmpty && username != name)
                                  Text(
                                    username,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onPrimaryContainer
                                          .withValues(alpha: 0.8),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: scheme.onPrimaryContainer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              for (final item in [
                ('设置', Icons.settings_outlined, Icons.settings),
                ('关于', Icons.info_outline, Icons.info),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 2,
                  ),
                  child: ListTile(
                    shape: const StadiumBorder(),
                    selected: _utilityPage == item.$1,
                    selectedTileColor: scheme.secondaryContainer,
                    selectedColor: scheme.onSecondaryContainer,
                    leading: Icon(_utilityPage == item.$1 ? item.$3 : item.$2),
                    title: Text(item.$1),
                    onTap: () => open(drawerContext, item.$1),
                  ),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    Navigator.of(drawerContext).pop();
                    _logout();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('退出登录'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _logout() {
    if (widget.writeState.intent != null) return;
    unawaited(widget.onLogout());
  }
}

/// 底栏顶部留白 8pt，底部安全区最多保留 20pt，仍避开 Home 指示条。
class _CompactNavigationBar extends StatelessWidget {
  const _CompactNavigationBar({required this.child});

  static const double _topGap = 8;
  static const double _maxBottomInset = 20;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    return ColoredBox(
      color:
          theme.navigationBarTheme.backgroundColor ??
          theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.only(top: _topGap),
        child: MediaQuery(
          data: media.copyWith(
            padding: media.padding.copyWith(
              bottom: media.padding.bottom > _maxBottomInset
                  ? _maxBottomInset
                  : media.padding.bottom,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
