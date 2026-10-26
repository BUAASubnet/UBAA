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
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('关于'),
                  onTap: () => _openUtility('关于'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRailLeading(BuildContext context, bool extended) {
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
      onTap: () {
        _openUtility('我的资料');
      },
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

  Drawer _buildDrawer(BuildContext context) => Drawer(
    child: SafeArea(
      child: Column(
        children: <Widget>[
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
            accountName: Text(
              widget.user?.preferredName ?? 'UBAA',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            accountEmail: Text(
              widget.user?.username == widget.user?.preferredName
                  ? ''
                  : widget.user?.username ?? '',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            currentAccountPicture: CircleAvatar(
              child: Text((widget.user?.preferredName ?? 'U').characters.first),
            ),
          ),
          for (final item in [
            ('我的资料', Icons.person_outline),
            ('设置', Icons.settings_outlined),
            ('关于', Icons.info_outline),
          ])
            ListTile(
              leading: Icon(item.$2),
              title: Text(item.$1),
              onTap: () {
                Navigator.of(context).pop();
                _openUtility(item.$1);
              },
            ),
        ],
      ),
    ),
  );
}
