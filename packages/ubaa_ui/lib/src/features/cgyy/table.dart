part of 'reservation_flow.dart';

extension CgyyReservationTable on CgyyReservationFlowState {
  Map<String, CgyyReserveAction> get _actions =>
      _busy ? const {} : _eligibleActions;

  /// 不看加载状态的可预约集合，供“只看可预约”在切换期间保持表格稳定。
  Map<String, CgyyReserveAction> get _eligibleActions {
    final day = _day;
    if (day == null) return {};
    final result = <String, CgyyReserveAction>{};
    for (final detail in _view.details) {
      final p = detail.presentation;
      final action = detail.action<CgyyReserveAction>();
      if (p is! CgyySlotPresentation ||
          action == null ||
          action.eligibility != ActionEligibility.allowed ||
          action.venueSiteId <= 0 ||
          action.spaceId <= 0 ||
          action.timeId <= 0 ||
          action.timeOrdinal < 0 ||
          (action.venueSpaceGroupId != null &&
              action.venueSpaceGroupId! <= 0) ||
          action.venueSiteId != day.venueSiteId ||
          action.venueSiteId != p.venueSiteId ||
          action.reservationDate.trim() != day.reservationDate ||
          p.reservationDate != day.reservationDate ||
          action.spaceId != p.spaceId ||
          action.timeId != p.timeId ||
          action.venueSpaceGroupId != p.venueSpaceGroupId ||
          day.timeSlots.where((time) => time.id == p.timeId).length != 1 ||
          day.spaces
                  .where(
                    (space) =>
                        space.spaceId == p.spaceId &&
                        space.venueSiteId == p.venueSiteId &&
                        space.venueSpaceGroupId == p.venueSpaceGroupId,
                  )
                  .length !=
              1 ||
          _view.details
                  .where(
                    (d) =>
                        d.presentation is CgyySlotPresentation &&
                        (d.presentation! as CgyySlotPresentation).spaceId ==
                            p.spaceId &&
                        (d.presentation! as CgyySlotPresentation).timeId ==
                            p.timeId,
                  )
                  .length !=
              1)
        continue;
      result[uiCgyyActionKey(action)] = action;
    }
    return result;
  }

  Widget _table(BuildContext context, CgyyDayPresentation day) {
    if (day.spaces.isEmpty)
      return const Padding(padding: EdgeInsets.all(24), child: Text('暂无研讨室'));
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final rowHeight = 56 * scale;
    final headerHeight = 62 * scale;
    final border = Border.all(
      color: Theme.of(context).colorScheme.outlineVariant,
      width: .5,
    );
    Widget cell(
      String label,
      double width,
      double height, {
      Widget? child,
      TextAlign align = TextAlign.center,
    }) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(border: border),
      alignment: Alignment.center,
      padding: child == null
          ? const EdgeInsets.symmetric(horizontal: 8)
          : EdgeInsets.zero,
      child:
          child ??
          Tooltip(
            message: label,
            child: Text(
              label,
              textAlign: align,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
    );
    final allTimes = <CgyyTimePresentation>[
      ...day.timeSlots,
      for (final id
          in _view.details
              .map((d) => d.presentation)
              .whereType<CgyySlotPresentation>()
              .map((p) => p.timeId)
              .toSet())
        if (!day.timeSlots.any((time) => time.id == id))
          CgyyTimePresentation(
            id: id,
            beginTime: '',
            endTime: '',
            label: '时段 $id',
          ),
    ];
    final actions = _actions;
    final eligible = _eligibleActions;
    bool open(CgyySpacePresentation space, CgyyTimePresentation time) =>
        eligible.containsKey(_slotKey(space, time));
    final spaces = widget.onlyAvailable
        ? day.spaces.where((s) => allTimes.any((t) => open(s, t))).toList()
        : day.spaces;
    final times = widget.onlyAvailable
        ? allTimes.where((t) => spaces.any((s) => open(s, t))).toList()
        : allTimes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spaces.isEmpty && _busy)
          const Spacer()
        else if (spaces.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('这一天该楼层没有可预约时段'),
                  if (widget.onShowAll case final showAll?)
                    TextButton(onPressed: showAll, child: const Text('显示全部时段')),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final roomWidth = 88 * scale;
                final timeWidth = math.max(
                  76 * scale,
                  (constraints.maxWidth - roomWidth) /
                      math.max(times.length, 1),
                );
                return CustomScrollView(
                  key: const ValueKey('cgyy-room-rows'),
                  slivers: [
                    if (!_busy && _view.evidence?.complete == false)
                      const SliverToBoxAdapter(child: Text('查询范围尚未更新完整')),
                    if (_view.status == FeatureLoadStatus.stale &&
                        _view.error != null)
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FriendlyErrorCard(
                              error: _view.error!,
                              onRetry: widget.onRetry,
                            ),
                          ],
                        ),
                      ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: CgyyTableHeader(
                        height: headerHeight,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          child: Row(
                            children: [
                              cell('研讨室', roomWidth, headerHeight),
                              Expanded(
                                child: SingleChildScrollView(
                                  key: const ValueKey(
                                    'cgyy-time-header-scroll',
                                  ),
                                  controller: _headerTimes,
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      for (final time in times)
                                        cell(
                                          time.beginTime.isEmpty
                                              ? '${time.label}\n信息不完整'
                                              : '${_clock(time.beginTime)}\n–${_clock(time.endTime)}',
                                          timeWidth,
                                          headerHeight,
                                          // 整块居中、两行右对齐，起止时间末位对齐。
                                          align: TextAlign.right,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              for (final space in spaces)
                                cell(space.spaceName, roomWidth, rowHeight),
                            ],
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              key: const ValueKey('cgyy-time-body-scroll'),
                              controller: _bodyTimes,
                              scrollDirection: Axis.horizontal,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final space in spaces)
                                    Row(
                                      children: [
                                        for (final time in times)
                                          cell(
                                            '',
                                            timeWidth,
                                            rowHeight,
                                            child: _slotCell(
                                              context,
                                              space,
                                              time,
                                              actions,
                                            ),
                                          ),
                                      ],
                                    ),
                                  if (times.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('暂无时段'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  /// 表头分两行并去掉前导零，压缩列宽：08:00 → 8:00。
  static String _clock(String value) =>
      value.startsWith('0') && value.length > 4 ? value.substring(1) : value;

  String? _slotKey(CgyySpacePresentation space, CgyyTimePresentation time) {
    final candidates = _view.details.where((d) {
      final p = d.presentation;
      return p is CgyySlotPresentation &&
          p.spaceId == space.spaceId &&
          p.venueSiteId == space.venueSiteId &&
          p.venueSpaceGroupId == space.venueSpaceGroupId &&
          p.timeId == time.id;
    }).toList();
    if (candidates.length != 1) return null;
    final action = candidates.single.action<CgyyReserveAction>();
    return action == null ? null : uiCgyyActionKey(action);
  }

  Widget _slotCell(
    BuildContext context,
    CgyySpacePresentation space,
    CgyyTimePresentation time,
    Map<String, CgyyReserveAction> actions,
  ) {
    final candidates = _view.details.where((d) {
      final p = d.presentation;
      return p is CgyySlotPresentation &&
          p.spaceId == space.spaceId &&
          p.venueSiteId == space.venueSiteId &&
          p.venueSpaceGroupId == space.venueSpaceGroupId &&
          p.timeId == time.id;
    }).toList();
    final detail = candidates.length == 1 ? candidates.single : null;
    final p = detail?.presentation as CgyySlotPresentation?;
    final candidate = detail?.action<CgyyReserveAction>();
    final key = candidate == null ? null : uiCgyyActionKey(candidate);
    final allowed = key != null && actions.containsKey(key);
    final selected = allowed && _selected.contains(key);
    final colors = Theme.of(context).colorScheme;
    final status = selected
        ? '已选'
        : allowed
        ? '可预约'
        : candidates.isEmpty
        ? '无时段信息'
        : p?.reservationStatus == null
        ? '资格未知'
        : '不可预约';
    final toggle = allowed ? () => _toggleSlot(key, actions) : null;
    return Semantics(
      label:
          '${space.spaceName} ${_day?.reservationDate ?? ''} ${time.beginTime}–${time.endTime} $status',
      button: true,
      enabled: allowed,
      selected: selected,
      onTap: toggle,
      excludeSemantics: true,
      child: SizedBox.expand(
        child: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(),
            backgroundColor: selected
                ? colors.primary
                : allowed
                ? colors.primaryContainer
                : colors.surface,
            foregroundColor: selected
                ? colors.onPrimary
                : colors.onPrimaryContainer,
            disabledForegroundColor: colors.onSurfaceVariant,
          ),
          onPressed: toggle,
          child: selected
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '已选',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: colors.onPrimary),
                    ),
                  ],
                )
              : allowed
              ? const Icon(Icons.add, size: 20)
              : status == '不可预约'
              ? const Icon(Icons.remove, size: 20)
              : Text(
                  status == '无时段信息' ? '—' : status,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}
