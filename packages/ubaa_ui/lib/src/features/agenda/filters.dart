part of 'view.dart';

extension _AgendaFilters on AgendaViewState {
  Widget _buildFilters({VoidCallback? onUpdate}) {
    void apply(VoidCallback action) {
      update(action);
      onUpdate?.call();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('事项来源', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final source in [
              '全部',
              '课程',
              '作业',
              '博雅',
              '考试',
              '研讨室',
              '签到',
              '阳光打卡',
              '我的',
            ])
              ChoiceChip(
                label: Text(source),
                selected: filter == source,
                onSelected: (_) => apply(() => filter = source),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('仅看待办'),
          value: todos,
          onChanged: (value) => apply(() => todos = value),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('显示已完成'),
          value: includeCompleted,
          onChanged: (value) => apply(() => includeCompleted = value),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('显示已隐藏'),
          value: includeHidden,
          onChanged: (value) => apply(() => includeHidden = value),
        ),
      ],
    );
  }

  Future<void> _showFilters() async {
    await showUiSheet<void>(
      context,
      builder: (context) => bound(
        StatefulBuilder(
          builder: (context, refresh) => UiSheetBody(
            title: '筛选日程',
            children: [filters(onUpdate: () => refresh(() {}))],
            primaryAction: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            ),
            actions: [
              OutlinedButton(
                onPressed: () {
                  update(() {
                    filter = '全部';
                    todos = false;
                    includeCompleted = true;
                    includeHidden = false;
                  });
                  refresh(() {});
                },
                child: const Text('重置'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickFilters() => SizedBox(
    height: 40,
    child: ListView.separated(
      key: const ValueKey('agenda-quick-filters'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: AgendaViewState._quickFilters.length,
      separatorBuilder: (_, _) => const SizedBox(width: 6),
      itemBuilder: (context, i) {
        final name = AgendaViewState._quickFilters[i];
        final selected = name == '待办'
            ? todos
            : name == '全部'
            ? filter == '全部' && !todos
            : filter == name;
        return ChoiceChip(
          label: Text(name),
          selected: selected,
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => update(() {
            if (name == '待办') {
              todos = !todos;
            } else if (name == '全部') {
              filter = '全部';
              todos = false;
            } else {
              filter = filter == name ? '全部' : name;
            }
          }),
        );
      },
    ),
  );
}
