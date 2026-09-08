part of '../../widgets.dart';

extension _CgyyReservationTable on _CgyyReservationFlowState {
  Map<String, CgyyReserveAction> get _actions {
    final day = _day;
    if (day == null) return {};
    final result = <String, CgyyReserveAction>{};
    for (final detail in widget.snapshot.details) {
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
          widget.snapshot.details
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
      result[_cgyyActionKey(action)] = action;
    }
    return result;
  }

  Widget _table(BuildContext context, CgyyDayPresentation day) {
    final filter = widget.filter.trim().toLowerCase();
    final spaces = day.spaces
        .where(
          (space) =>
              filter.isEmpty ||
              space.spaceName.toLowerCase().contains(filter) ||
              widget.snapshot.details.any(
                (d) =>
                    d.presentation is CgyySlotPresentation &&
                    (d.presentation! as CgyySlotPresentation).spaceId ==
                        space.spaceId &&
                    [
                      d.title,
                      ...d.fields.expand((f) => [f.label, f.value]),
                    ].any((value) => value.toLowerCase().contains(filter)),
              ),
        )
        .toList();
    if (spaces.isEmpty)
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('没有匹配的研讨室'),
      );
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final rowHeight = 56 * scale;
    final headerHeight = 62 * scale;
    final border = Border.all(
      color: Theme.of(context).colorScheme.outlineVariant,
      width: .5,
    );
    Widget cell(String label, double width, double height, {Widget? child}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(border: border),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child:
              child ??
              Tooltip(
                message: label,
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        );
    final times = <CgyyTimePresentation>[
      ...day.timeSlots,
      for (final id
          in widget.snapshot.details
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 房间列固定，横向移动时段时保留上下文。
        Column(
          children: [
            cell('教室', 112 * scale, headerHeight),
            for (final space in spaces)
              cell(space.spaceName, 112 * scale, rowHeight),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (final time in times)
                      cell(
                        time.beginTime.isEmpty
                            ? '${time.label}\n信息不完整'
                            : '${time.beginTime}\n–${time.endTime}',
                        86 * scale,
                        headerHeight,
                      ),
                  ],
                ),
                for (final space in spaces)
                  Row(
                    children: [
                      for (final time in times)
                        cell(
                          '',
                          86 * scale,
                          rowHeight,
                          child: _slotCell(context, space, time, actions),
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
    );
  }

  Widget _slotCell(
    BuildContext context,
    CgyySpacePresentation space,
    CgyyTimePresentation time,
    Map<String, CgyyReserveAction> actions,
  ) {
    final candidates = widget.snapshot.details.where((d) {
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
    final key = candidate == null ? null : _cgyyActionKey(candidate);
    final allowed = key != null && actions.containsKey(key);
    final selected = allowed && _selected.contains(key);
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: '${space.spaceName} ${time.beginTime}–${time.endTime}',
      child: SizedBox.expand(
        child: TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(),
            backgroundColor: selected
                ? colors.primary
                : allowed
                ? colors.primaryContainer
                : Colors.transparent,
            foregroundColor: selected ? colors.onPrimary : colors.onSurface,
            disabledForegroundColor: colors.onSurfaceVariant,
          ),
          onPressed: !allowed ? null : () => _toggleSlot(key, actions),
          child: Text(
            selected
                ? '已选'
                : allowed
                ? '可预约'
                : candidates.isEmpty
                ? '—'
                : p?.reservationStatus == null
                ? '资格未知'
                : '不可预约',
            style: TextStyle(
              fontSize: Theme.of(context).textTheme.labelSmall?.fontSize,
            ),
          ),
        ),
      ),
    );
  }
}
