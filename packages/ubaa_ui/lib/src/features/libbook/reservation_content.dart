part of '../../widgets.dart';

extension _LibbookReservationContent on _LibbookReservationFlowState {
  Widget _areaDetail(
    BuildContext context,
    LibbookAreaDetailPresentation area,
  ) => Card(
    margin: const EdgeInsets.only(top: 4, bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(area.name, style: Theme.of(context).textTheme.titleMedium),
          if (area.availableDates.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('可用日期：${area.availableDates.join('、')}'),
          ],
          if (area.timeSlots.isNotEmpty) ...[
            _section('时段'),
            for (final slot in area.timeSlots)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SelectableText(
                  '${slot.label} · ${slot.start}–${slot.end}\n时段编号：${slot.id}',
                ),
              ),
            const Text('当前时段未标明适用日期，请核对日期和时段后查询座位。'),
          ] else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('当前未提供时段信息。'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: area.id.trim().isEmpty
                ? null
                : () => widget.onSeatQuery(
                    FeatureQuery(
                      view: FeatureQueryView.libbookSeats,
                      areaId: area.id,
                      segment: '',
                      startTime: '',
                      endTime: '',
                    ),
                  ),
            icon: const Icon(Icons.event_seat_outlined),
            label: const Text('查询座位'),
          ),
        ],
      ),
    ),
  );

  Widget _seatGrid(BuildContext context, List<FeatureDetail> details) {
    final seats = details.where((detail) {
      final p = detail.presentation;
      return p is LibbookSeatPresentation &&
          _matchesDetail(detail, [
            p.id,
            p.name,
            p.number,
            p.statusName,
            p.status?.toString() ?? '',
            p.areaId,
            p.queryDate,
            p.segment,
            p.startTime,
            p.endTime,
          ]);
    }).toList();
    final selected = details.where(
      (d) =>
          d.presentation is LibbookSeatPresentation &&
          (d.presentation! as LibbookSeatPresentation).id == _selectedSeat,
    );
    final selectedDetail = selected.length == 1 ? selected.single : null;
    final action = selectedDetail?.action<LibbookReserveAction>();
    final p = selectedDetail?.presentation as LibbookSeatPresentation?;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('座位'),
        if (seats.isEmpty) const Text('没有匹配的座位'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisExtent:
                100 *
                (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1, 2),
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: seats.length,
          itemBuilder: (context, index) {
            final detail = seats[index];
            final seat = detail.presentation! as LibbookSeatPresentation;
            final target = detail.action<LibbookReserveAction>();
            final unique =
                seats
                    .where(
                      (d) =>
                          (d.presentation! as LibbookSeatPresentation).id ==
                          seat.id,
                    )
                    .length ==
                1;
            final canSelect =
                unique && widget.onReserve != null && _canReserveSeat(target);
            final status =
                target == null ||
                    target.eligibility == ActionEligibility.unknown
                ? '资格未确认'
                : target.eligibility == ActionEligibility.denied
                ? '不可预约'
                : seat.statusName;
            return Card(
              color: _selectedSeat == seat.id
                  ? theme.colorScheme.primaryContainer
                  : null,
              child: InkWell(
                onTap: canSelect ? () => _toggleSeat(seat.id) : null,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.event_seat_outlined,
                        size: 22,
                        color: canSelect
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        seat.number.isEmpty ? seat.name : seat.number,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                      ),
                      Text(
                        status.isEmpty ? '状态未说明' : status,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        if (p != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已选座位：${p.number}', style: theme.textTheme.titleMedium),
                  Text('${p.queryDate} ${p.startTime}–${p.endTime}'),
                  Text(p.name),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _canReserveSeat(action) && widget.onReserve != null
                        ? () => widget.onReserve!(action!)
                        : null,
                    icon: const Icon(Icons.event_available),
                    label: const Text('准备预约此座位'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

bool _canReserveSeat(LibbookReserveAction? action) =>
    action?.eligibility == ActionEligibility.allowed &&
    [
      action!.areaId,
      action.seatId,
      action.day,
      action.segment,
      action.startTime,
      action.endTime,
    ].every((v) => v.trim().isNotEmpty);
