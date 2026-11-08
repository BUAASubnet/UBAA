part of 'view.dart';

extension _IhomeFilters on _IhomeViewState {
  void _submitSearch(String value) {
    _keyword = value.trim();
    unawaited(_load(reset: true));
  }

  List<(IhomeFilter, String)> get _sortOptions => [
    (IhomeFilter.all, '默认排序'),
    (IhomeFilter.newest, '最新发布'),
    if (_scope == IhomeScope.public) (IhomeFilter.oldest, '最早发布'),
    if (_scope == IhomeScope.mine) (IhomeFilter.replyTime, '回复时间'),
    (IhomeFilter.replied, '已回复'),
    (IhomeFilter.unreplied, '未回复'),
  ];

  List<Widget> _filters() => [
    if (_scope == IhomeScope.public)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        // 与其他功能页的搜索框保持同样的外观和高度。
        child: UiSearchField(
          controller: _search,
          enabled: _busy.isEmpty,
          maxLength: 200,
          hintText: '搜索诉求或回复',
          onClear: () {
            _search.clear();
            if (_keyword.isEmpty) return _update(() {});
            _submitSearch('');
          },
          onChanged: (_) => _update(() {}),
          onSubmitted: _submitSearch,
        ),
      ),
    if (_scope == IhomeScope.public || _scope == IhomeScope.mine)
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              _IhomeMenuChip<IhomeFilter>(
                tooltip: '排序与状态',
                icon: Icons.sort,
                value: _filter,
                options: _sortOptions,
                onSelected: _busy.isNotEmpty
                    ? null
                    : (v) {
                        _setFilter(v);
                        unawaited(_load(reset: true));
                      },
              ),
              if (_scope == IhomeScope.public && _config != null)
                _IhomeMenuChip<int>(
                  tooltip: '分类',
                  icon: Icons.category_outlined,
                  value: _category ?? 0,
                  options: [
                    (0, '全部分类'),
                    for (final c in _config!.categories) (c.id, c.name),
                  ],
                  onSelected: _busy.isNotEmpty
                      ? null
                      : (v) {
                          _setCategory(v);
                          unawaited(_load(reset: true));
                        },
                ),
            ],
          ),
        ),
      ),
  ];
}

/// 紧凑的单选菜单：芯片显示当前项，点开列出全部选项。
class _IhomeMenuChip<T> extends StatelessWidget {
  const _IhomeMenuChip({
    required this.tooltip,
    required this.icon,
    required this.value,
    required this.options,
    required this.onSelected,
  });
  final String tooltip;
  final IconData icon;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    final label =
        options.where((o) => o.$1 == value).firstOrNull?.$2 ?? options.first.$2;
    return MenuAnchor(
      menuChildren: [
        for (final (option, text) in options)
          MenuItemButton(
            leadingIcon: Icon(option == value ? Icons.check : null, size: 18),
            onPressed: () {
              if (option != value) onSelected?.call(option);
            },
            child: Text(text),
          ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: tooltip,
        child: ActionChip(
          avatar: Icon(icon, size: 18),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
          onPressed: onSelected == null
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }
}
