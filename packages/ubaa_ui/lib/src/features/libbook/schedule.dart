part of 'reservation_flow.dart';

extension LibbookReservationSchedule on LibbookReservationFlowState {
  bool _validArea(LibbookAreaPresentation area) =>
      area.id.trim().isNotEmpty &&
      // 缺省父字段不构成冲突；明确不同的父字段不能被选择。
      (area.premisesId.trim().isEmpty || area.premisesId == _libraryId) &&
      (_storeyId == null ||
          area.storeyId.trim().isEmpty ||
          area.storeyId == _storeyId) &&
      _areas
              .where(
                (detail) =>
                    detail.presentation is LibbookAreaPresentation &&
                    (detail.presentation! as LibbookAreaPresentation).id ==
                        area.id,
              )
              .length ==
          1;

  void _clearAreaSelection() {
    _areaSchedule = null;
    _reservationDay = _slotId = _selectedSeat = null;
    _hideSeats = true;
  }

  void _consumeAreaSchedule(List<FeatureDetail> details) {
    final p = details.length == 1 ? details.single.presentation : null;
    final previousArea = _areaSchedule?.id;
    _areaSchedule =
        p is LibbookAreaSchedulePresentation && p.id == widget.query.areaId
        ? p
        : null;
    if (_areaSchedule == null ||
        previousArea != _areaSchedule!.id ||
        _selectedDay == null) {
      _reservationDay = _slotId = null;
    } else if (_selectedSlot == null) {
      _slotId = null;
    }
    _selectedSeat = null;
    _hideSeats = true;
    if (_selectedDay == null && _scheduleDays.isNotEmpty) {
      _reservationDay = _scheduleDays.first.day;
    }
    if (_selectedSlot == null && _scheduleSlots.isNotEmpty) {
      _slotId = _scheduleSlots.first.id;
    }
    if (_selectedDay != null && _selectedSlot != null) {
      final query = _seatDraft;
      _schedule(() => _read(query));
    }
  }

  List<LibbookDaySchedulePresentation> get _scheduleDays {
    final days =
        _areaSchedule?.days ?? const <LibbookDaySchedulePresentation>[];
    if (days.any(
      (day) =>
          days.where((other) => other.day.trim() == day.day.trim()).length != 1,
    )) {
      return const [];
    }
    return days.where((day) => _parsedDay(day.day) != null).toList();
  }

  LibbookDaySchedulePresentation? get _selectedDay {
    final matches = _scheduleDays.where((day) => day.day == _reservationDay);
    return matches.length == 1 ? matches.single : null;
  }

  List<LibbookTimeSlotPresentation> get _scheduleSlots {
    final slots =
        _selectedDay?.timeSlots ?? const <LibbookTimeSlotPresentation>[];
    return slots
        .where(
          (slot) =>
              [
                slot.id,
                slot.start,
                slot.end,
              ].every((value) => value.trim().isNotEmpty) &&
              slots.where((other) => other.id == slot.id).length == 1,
        )
        .toList();
  }

  LibbookTimeSlotPresentation? get _selectedSlot {
    final matches = _scheduleSlots.where((slot) => slot.id == _slotId);
    return matches.length == 1 ? matches.single : null;
  }

  FeatureQuery get _seatDraft => FeatureQuery(
    view: FeatureQueryView.libbookSeats,
    areaId: _areaSchedule?.id,
    date: _parsedDay(_reservationDay ?? ''),
    segment: _selectedSlot?.id ?? '',
    startTime: _selectedSlot?.start ?? '',
    endTime: _selectedSlot?.end ?? '',
  );

  bool _matchesScheduleQuery(FeatureQuery query) =>
      _selectedDay != null &&
      _selectedSlot != null &&
      _seatDraft.hasSameParameters(query);

  void _chooseDay(String? day) {
    _change(() {
      _reservationDay = day;
      _slotId = _selectedSeat = null;
      _hideSeats = true;
      _generation++;
    });
    if (_scheduleSlots.isNotEmpty) _slotId = _scheduleSlots.first.id;
    if (_selectedSlot != null) unawaited(_read(_seatDraft));
  }

  void _chooseSlot(String? id) {
    _change(() {
      _slotId = id;
      _selectedSeat = null;
      _hideSeats = true;
      _generation++;
    });
    if (_selectedSlot != null) unawaited(_read(_seatDraft));
  }

  bool _seatBelongsToQuery(
    LibbookSeatPresentation seat,
    LibbookReserveAction? action,
  ) {
    final query = widget.query;
    if (query.view != FeatureQueryView.libbookSeats) return false;
    final day = query.date == null ? null : _date(query.date!);
    return seat.areaId == query.areaId &&
        seat.queryDate == day &&
        seat.segment == query.segment &&
        seat.startTime == query.startTime &&
        seat.endTime == query.endTime &&
        (action == null ||
            (action.areaId == query.areaId &&
                action.day == day &&
                action.segment == query.segment &&
                action.startTime == query.startTime &&
                action.endTime == query.endTime));
  }

  Widget _scheduleDetail(
    BuildContext context,
    LibbookAreaSchedulePresentation area,
  ) {
    final days = _scheduleDays;
    final slots = _scheduleSlots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (days.length > 1)
          _chipRow('日期', _reservationDay, {
            for (final day in days) day.day: uiShortDateTime(day.day),
          }, _chooseDay),
        if (days.isEmpty) const Text('当前分区暂无可用日期。'),
        if (_selectedDay != null && slots.length > 1)
          _chipRow('时段', _slotId, {
            for (final slot in slots)
              slot.id: '${slot.label} ${slot.start}–${slot.end}',
          }, _chooseSlot),
        if (_selectedDay != null && slots.isEmpty) Text('当前日期暂无可用时段。'),
        // 只有一个日期/时段时不再单独写一行，避免与上方选项重复。
      ],
    );
  }
}
