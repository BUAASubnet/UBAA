part of 'reservation_flow.dart';

extension CgyyReservationChoices on CgyyReservationFlowState {
  Widget buildInlineChips(BuildContext context) {
    final campuses = _sites.map((s) => s.campusName).toSet().toList()
      ..sort((a, b) => _campusRank(a).compareTo(_campusRank(b)));
    final day = _day;
    final dates = [
      for (final date in day?.availableDates.toSet() ?? const <String>{})
        if (_parseDay(date) != null) date,
    ];
    // 固定顺序：日期、校区与开关、楼层。数据未到时原位放占位，避免整行插入造成跳动。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChoiceStrip(
          key: const ValueKey('cgyy-dates'),
          children: dates.isEmpty
              ? [
                  FilterChip(
                    key: const ValueKey('cgyy-date-placeholder'),
                    label: Text(
                      day == null &&
                              widget.snapshot.status !=
                                  FeatureLoadStatus.failure
                          ? '正在读取日期'
                          : '暂无可选日期',
                    ),
                    onSelected: null,
                  ),
                ]
              : [
                  for (final date in dates)
                    FilterChip(
                      key: ValueKey('cgyy-date-$date'),
                      tooltip: date,
                      label: Text(_dateLabel(date)),
                      selected: day!.reservationDate == date,
                      onSelected: _busy || widget.onQuery == null
                          ? null
                          : (_) => unawaited(
                              _selectSite(day.venueSiteId, _parseDay(date)),
                            ),
                    ),
                ],
        ),
        Row(
          children: [
            Expanded(
              child: _ChoiceStrip(
                key: const ValueKey('cgyy-campuses'),
                trailingPadding: false,
                children: [
                  for (final campus in ['全部', ...campuses])
                    FilterChip(
                      key: ValueKey('cgyy-campus-${_campusLabel(campus)}'),
                      label: Text(_campusLabel(campus)),
                      selected: _campus == campus,
                      onSelected:
                          _busy || widget.onQuery == null || _sites.isEmpty
                          ? null
                          : (_) => _selectCampus(campus, day),
                    ),
                ],
              ),
            ),
            FilterChip(
              key: const ValueKey('cgyy-only-available'),
              label: const Text('只看可预约'),
              selected: _onlyAvailable,
              onSelected: (value) => _change(() => _onlyAvailable = value),
            ),
            PopupMenuButton<void>(
              tooltip: '图例',
              icon: const Icon(Icons.info_outline),
              itemBuilder: (_) => [
                const PopupMenuItem<void>(
                  // 点按即关闭；保持可用状态以免图例颜色被调淡。
                  child: CgyySlotLegend(),
                ),
              ],
            ),
            SizedBox(
              width: math.max(
                0,
                UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width) - 8,
              ),
            ),
          ],
        ),
        if (_visibleSites.isNotEmpty)
          _ChoiceStrip(
            key: const ValueKey('cgyy-sites'),
            children: [
              for (final site in _visibleSites)
                FilterChip(
                  key: ValueKey('cgyy-site-${site.id}'),
                  label: Text(_siteLabel(site)),
                  selected: _site == site.id,
                  onSelected: _busy || widget.onQuery == null
                      ? null
                      : (_) => unawaited(
                          _selectSite(
                            site.id,
                            _parseDay(day?.reservationDate) ??
                                widget.query.date,
                          ),
                        ),
                ),
            ],
          ),
      ],
    );
  }

  void _selectCampus(String campus, CgyyDayPresentation? day) {
    _change(() {
      _campus = campus;
      _selected.clear();
    });
    final sites = _visibleSites;
    if (sites.isEmpty) return;
    final previous = sites.where((s) => s.id == _site);
    unawaited(
      _selectSite(
        (previous.isEmpty ? sites.first : previous.single).id,
        _parseDay(day?.reservationDate) ?? widget.query.date,
      ),
    );
  }

  String _dateLabel(String value) {
    final date = _parseDay(value);
    if (date == null) return value;
    final now = homeCampusTime(clock.now());
    final today =
        date.year == now.year && date.month == now.month && date.day == now.day;
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final prefix = date.year == now.year ? '' : '${date.year}年';
    return '$prefix${date.month}月${date.day}日 ${today ? '今天' : weekdays[date.weekday - 1]}';
  }
}

/// 保留旧版横向直选；手机滑动，桌面换行铺开。
class _ChoiceStrip extends StatelessWidget {
  const _ChoiceStrip({
    super.key,
    required this.children,
    this.trailingPadding = true,
  });
  final List<Widget> children;

  /// 同一行右侧还有固定控件时不留页边距。
  final bool trailingPadding;

  @override
  Widget build(BuildContext context) {
    // 组间留 12，组内换行 6，日期、校区、楼层三组一眼分开。
    final insets = UbaaTheme.pageInsets(context, top: 6, bottom: 6);
    return UiChipStrip(
      padding: trailingPadding ? insets : insets.copyWith(right: 4),
      children: children,
    );
  }
}
