part of 'view.dart';

extension _AgendaToolbar on AgendaViewState {
  Widget _buildToolbar() => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      MediaQuery.paddingOf(context).top + 4,
      4,
      0,
    ),
    child: SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                '日程',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          // 刷新进度：下拉期间已有下拉指示器，不重复显示。
          if (loading && result != null && !pulling)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: LoadingGlyph(),
            ),
          IconButton(
            tooltip: '搜索日程',
            isSelected: searchVisible,
            onPressed: () => update(() {
              searchVisible = !searchVisible;
              if (!searchVisible) {
                searchField.clear();
                search = '';
              }
            }),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: '筛选日程',
            onPressed: showFilters,
            icon: Badge(
              isLabelVisible: selectedFilterCount > 0,
              label: Text('$selectedFilterCount'),
              child: const Icon(Icons.tune),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多日程操作',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'export':
                  unawaited(export());
                case 'refresh':
                  unawaited(load());
                case 'school':
                  unawaited(refreshSchool());
                case 'import':
                  importSchedule();
                case 'data':
                  unawaited(dataSheet());
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const ValueKey('agenda-data-menu'),
                value: 'data',
                enabled: available,
                child: const ListTile(
                  leading: Icon(Icons.storage_outlined),
                  title: Text('数据与同步'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                enabled: available && !busy,
                child: const ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('导出日历'),
                ),
              ),
              PopupMenuItem(
                value: 'school',
                enabled: available,
                child: const ListTile(
                  leading: Icon(Icons.cloud_download_outlined),
                  title: Text('刷新学校日程'),
                ),
              ),
              PopupMenuItem(
                value: 'import',
                enabled: available,
                child: const ListTile(
                  leading: Icon(Icons.calendar_month_outlined),
                  title: Text('导入整学期课表'),
                ),
              ),
              PopupMenuItem(
                value: 'refresh',
                enabled: !loading,
                child: const ListTile(
                  leading: Icon(Icons.refresh),
                  title: Text('重新加载'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _buildViewControls() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final prev = mode == AgendaViewMode.month ? '上一月' : '上一周';
    final next = mode == AgendaViewMode.month ? '下一月' : '下一周';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: range,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            customRange
                                ? rangeLabel
                                : '${focusDate.year == agendaDay(now).year ? '' : '${focusDate.year}年'}${focusDate.month}月',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: prev,
              onPressed: () => move(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: next,
              onPressed: () => move(1),
              icon: const Icon(Icons.chevron_right),
            ),
            // 只占一个图标位，不挤掉左侧月份；在今天时隐藏但保留位置，箭头不跳动。
            // 窄屏放大文字时顶栏放不下空位，此时不保留。
            Visibility(
              visible: !_onToday,
              maintainSize: MediaQuery.sizeOf(context).width >= 360,
              maintainAnimation: MediaQuery.sizeOf(context).width >= 360,
              maintainState: MediaQuery.sizeOf(context).width >= 360,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '回到今天',
                color: colors.primary,
                onPressed: () => goDate(agendaDay(now)),
                icon: const Icon(Icons.today),
              ),
            ),
            SegmentedButton<AgendaViewMode>(
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 6),
                ),
                minimumSize: const WidgetStatePropertyAll(Size(40, 36)),
                tapTargetSize: MaterialTapTargetSize.padded,
                textStyle: WidgetStatePropertyAll(theme.textTheme.labelMedium),
              ),
              segments: const [
                ButtonSegment(
                  value: AgendaViewMode.list,
                  label: Text('列表'),
                  tooltip: '列表视图',
                ),
                ButtonSegment(
                  value: AgendaViewMode.week,
                  label: Text('周'),
                  tooltip: '周视图',
                ),
                ButtonSegment(
                  value: AgendaViewMode.month,
                  label: Text('月'),
                  tooltip: '月视图',
                ),
              ],
              selected: {mode},
              onSelectionChanged: (value) => goMode(value.single),
            ),
          ],
        ),
      ],
    );
  }
}
