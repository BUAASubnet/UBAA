part of 'reservation_flow.dart';

extension LibbookReservationContent on LibbookReservationFlowState {
  Widget _seatGrid(BuildContext context, List<FeatureDetail> details) {
    final seats = details.where((detail) {
      final p = detail.presentation;
      return p is LibbookSeatPresentation && p.status == 1;
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
        const SizedBox(height: 12),
        if (seats.isEmpty) const Text('当前分区暂无可预约座位'),
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
                !_busy &&
                unique &&
                widget.onReserve != null &&
                uiCanReserveSeat(target) &&
                _seatBelongsToQuery(seat, target);
            final status =
                target == null ||
                    target.eligibility == ActionEligibility.unknown
                ? '资格未确认'
                : target.eligibility == ActionEligibility.denied
                ? '不可预约'
                : null;
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
                      if (status != null)
                        Text(
                          status,
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
                  if (p.name.trim().isNotEmpty &&
                      p.name.trim() != p.number.trim())
                    Text(p.name),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        !_busy &&
                            uiCanReserveSeat(action) &&
                            widget.onReserve != null &&
                            _seatBelongsToQuery(p, action)
                        ? () => widget.onReserve!(action!)
                        : null,
                    icon: const Icon(Icons.event_available),
                    label: const Text('预约此座位'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
