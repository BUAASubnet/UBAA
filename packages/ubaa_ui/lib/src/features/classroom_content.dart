part of '../widgets.dart';

/// 沿旧版楼栋分组和14节表格；只呈现已读取的原空闲令牌。
class _ClassroomContent extends StatefulWidget {
  const _ClassroomContent({required this.details, this.query, this.onQuery});
  final List<FeatureDetail> details;
  final FeatureQuery? query;
  final Future<void> Function(FeatureQuery)? onQuery;
  @override
  State<_ClassroomContent> createState() => _ClassroomContentState();
}

class _ClassroomContentState extends State<_ClassroomContent> {
  final _horizontal = ScrollController();
  final _searchController = TextEditingController();
  String? _selectedBuilding;

  @override
  void dispose() {
    _horizontal.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(
    BuildContext context,
    DateTime currentDate,
    int campus,
  ) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      helpText: '选择查询日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (selected == null || !mounted) return;
    setState(() => _selectedBuilding = null);
    final nextQuery = FeatureQuery(campus: campus, date: selected);
    widget.onQuery?.call(nextQuery);
  }

  // 表格可横滚，来源与楼栋标题始终留在可视宽度内。
  Widget _fixedColumn(double width, Widget child) => Align(
    alignment: Alignment.centerLeft,
    child: AnimatedBuilder(
      animation: _horizontal,
      child: SizedBox(width: width, child: child),
      builder: (context, child) => Transform.translate(
        offset: Offset(_horizontal.hasClients ? _horizontal.offset : 0, 0),
        child: child,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final first =
        widget.details.isNotEmpty &&
            widget.details.first.presentation is ClassroomPresentation
        ? widget.details.first.presentation! as ClassroomPresentation
        : null;
    final campus = widget.query?.campus ?? first?.campus ?? 1;
    final now = DateTime.now();
    final dateObj =
        widget.query?.date ??
        (first?.queryDate != null
            ? DateTime.tryParse(first!.queryDate!)
            : null) ??
        DateTime(now.year, now.month, now.day);
    final queryDate =
        '${dateObj.year.toString().padLeft(4, '0')}-${dateObj.month.toString().padLeft(2, '0')}-${dateObj.day.toString().padLeft(2, '0')}';

    final availableBuildings =
        widget.details
            .map((d) => (d.presentation as ClassroomPresentation).floorName)
            .toSet()
            .toList()
          ..sort();

    final searchQuery = _searchController.text.trim().toLowerCase();
    final filteredDetails = widget.details.where((d) {
      final p = d.presentation! as ClassroomPresentation;
      if (_selectedBuilding != null && p.floorName != _selectedBuilding) {
        return false;
      }
      if (searchQuery.isNotEmpty) {
        final titleMatch = d.title.toLowerCase().contains(searchQuery);
        final floorMatch = p.floorName.toLowerCase().contains(searchQuery);
        if (!titleMatch && !floorMatch) return false;
      }
      return true;
    }).toList();

    final wide = MediaQuery.sizeOf(context).width >= 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) ...[
          // 顶行：校区切换
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('学院路')),
                ButtonSegment(value: 2, label: Text('沙河')),
                ButtonSegment(value: 3, label: Text('杭州')),
              ],
              selected: {campus},
              onSelectionChanged: widget.onQuery == null
                  ? null
                  : (set) {
                      final newCampus = set.first;
                      if (newCampus != campus) {
                        setState(() => _selectedBuilding = null);
                        widget.onQuery?.call(
                          FeatureQuery(campus: newCampus, date: dateObj),
                        );
                      }
                    },
            ),
          ),
          // 次行：日期卡片 + 教室过滤
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.date_range, size: 18),
                    label: Text(
                      queryDate,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: widget.onQuery == null
                        ? null
                        : () => _pickDate(context, dateObj, campus),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索教室/楼栋',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          // 第三行：楼栋 FilterChips
          if (availableBuildings.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  for (final building in availableBuildings)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(building),
                        selected: _selectedBuilding == building,
                        onSelected: (selected) => setState(() {
                          _selectedBuilding = selected ? building : null;
                        }),
                      ),
                    ),
                ],
              ),
            ),
        ],
        // 第四行：主体表格
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = MediaQuery.textScalerOf(context).scale(11) / 11;
              final visibleWidth = math.max(0.0, constraints.maxWidth - 32);
              final width = math.max(visibleWidth, 324 * scale);
              final rowHeight = 44 * scale;
              final groups = <String, List<(int, FeatureDetail)>>{};
              for (final (index, detail) in filteredDetails.indexed) {
                final p = detail.presentation! as ClassroomPresentation;
                (groups[p.floorName] ??= []).add((index, detail));
              }
              final entries = <({String? group, (int, FeatureDetail)? item})>[
                for (final group in groups.entries) ...[
                  (group: group.key, item: null),
                  for (final item in group.value) (group: null, item: item),
                ],
              ];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: width > visibleWidth,
                  notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      height: constraints.maxHeight,
                      child: CustomScrollView(
                        key: const ValueKey('classroom-table-scroll'),
                        slivers: [
                          SliverToBoxAdapter(
                            child: _fixedColumn(
                              visibleWidth,
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (first case final f?
                                        when f.queryDate != null &&
                                            f.campus != null)
                                      Text(
                                        '${f.queryDate} · ${_classroomCampusName(f.campus!)}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          color: const Color(0xFF98FB98),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '空闲',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _ClassroomTableHeader(
                              height: 40 * scale,
                              controller: _horizontal,
                              nameWidth: width * 22 / 162,
                              theme: Theme.of(context),
                            ),
                          ),
                          SliverList.builder(
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              if (entry.group case final name?) {
                                return _fixedColumn(
                                  visibleWidth,
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Center(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.secondaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 4,
                                          ),
                                          child: Text(
                                            name.isEmpty ? '楼栋未说明' : name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSecondaryContainer,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final (rowIndex, detail) = entry.item!;
                              final p =
                                  detail.presentation! as ClassroomPresentation;
                              final free = p.sectionTokens
                                  .map(int.tryParse)
                                  .whereType<int>()
                                  .where((n) => n >= 1 && n <= 14)
                                  .toSet();
                              return SizedBox(
                                key: ValueKey('classroom-row-$rowIndex'),
                                height: rowHeight,
                                child: Stack(
                                  children: [
                                    Row(
                                      children: [
                                        const Expanded(
                                          flex: 22,
                                          child: SizedBox(),
                                        ),
                                        for (
                                          var section = 1;
                                          section <= 14;
                                          section++
                                        )
                                          Expanded(
                                            flex: 10,
                                            child: Tooltip(
                                              message:
                                                  '第$section节${free.contains(section) ? '空闲' : '未列为空闲'}',
                                              child: _ClassroomCell(
                                                color: free.contains(section)
                                                    ? const Color(0xFF98FB98)
                                                    : null,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    _ClassroomPinnedName(
                                      controller: _horizontal,
                                      width: width * 22 / 162,
                                      child: _ClassroomCell(
                                        child: InkWell(
                                          onTap: () => _showClassroomDetails(
                                            context,
                                            detail,
                                          ),
                                          child: Center(
                                            child: Text(
                                              detail.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 11,
                                                height: 12 / 11,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ClassroomCell extends StatelessWidget {
  const _ClassroomCell({this.child, this.color});
  final Widget? child;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    height: double.infinity,
    decoration: BoxDecoration(
      color: color,
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant,
        width: .5,
      ),
    ),
    child: child,
  );
}

class _ClassroomPinnedName extends AnimatedWidget {
  const _ClassroomPinnedName({
    required this.controller,
    required this.width,
    required this.child,
  }) : super(listenable: controller);
  final ScrollController controller;
  final double width;
  final Widget child;
  @override
  Widget build(BuildContext context) => Positioned(
    left: controller.hasClients ? controller.offset : 0,
    top: 0,
    bottom: 0,
    width: width,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: child,
    ),
  );
}

class _ClassroomTableHeader extends SliverPersistentHeaderDelegate {
  _ClassroomTableHeader({
    required this.height,
    required this.theme,
    required this.controller,
    required this.nameWidth,
  });
  final double height, nameWidth;
  final ThemeData theme;
  final ScrollController controller;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  Widget _label(String text) => _ClassroomCell(
    child: Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: theme.colorScheme.surface,
    child: Stack(
      children: [
        Row(
          children: [
            const Expanded(flex: 22, child: SizedBox()),
            for (var section = 1; section <= 14; section++)
              Expanded(flex: 10, child: _label('$section')),
          ],
        ),
        _ClassroomPinnedName(
          controller: controller,
          width: nameWidth,
          child: _label('教室'),
        ),
      ],
    ),
  );
  @override
  bool shouldRebuild(_ClassroomTableHeader oldDelegate) =>
      height != oldDelegate.height ||
      nameWidth != oldDelegate.nameWidth ||
      theme != oldDelegate.theme ||
      controller != oldDelegate.controller;
}

String _classroomCampusName(int campus) => switch (campus) {
  1 => '学院路',
  2 => '沙河',
  3 => '杭州',
  _ => '校区 $campus',
};

Future<void> _showClassroomDetails(BuildContext context, FeatureDetail detail) {
  final p = detail.presentation! as ClassroomPresentation;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(detail.title),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final field in <(String, String)>[
                ('楼栋', p.floorName),
                ('教室编号', p.roomId),
                ('楼栋/楼层编号', p.floorId),
                (
                  '原空闲节次',
                  p.availableSections.isEmpty ? '未提供' : p.availableSections,
                ),
                if (p.queryDate case final date?) ('查询日期', date),
                if (p.campus case final campus?)
                  ('校区', _classroomCampusName(campus)),
                for (final field in detail.fields) (field.label, field.value),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DetailField(label: field.$1, value: field.$2),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
