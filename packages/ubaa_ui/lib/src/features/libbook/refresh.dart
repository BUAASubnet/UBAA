part of 'reservation_flow.dart';

extension LibbookReservationRefresh on LibbookReservationFlowState {
  Future<void> _refreshAll() async {
    if (_busy || widget.onQuery == null) return;
    final token = Object();
    final date = widget.query.date ?? _parsedDay(_day ?? '');
    _change(() {
      _refreshToken = token;
      _selectedSeat = null;
      _hideSeats = true;
    });
    bool current() =>
        mounted &&
        identical(_refreshToken, token) &&
        TickerMode.valuesOf(context).enabled;
    Future<bool> read(FeatureQuery query) async {
      if (!current()) return false;
      await _read(query);
      if (!current()) return false;
      // 宿主 Future 完成后，等待对应快照进入本页再继续下一项读取。
      await WidgetsBinding.instance.endOfFrame;
      return current() &&
          widget.query.hasSameParameters(query) &&
          widget.snapshot.error == null &&
          widget.snapshot.evidence?.complete != false &&
          const {
            FeatureLoadStatus.success,
            FeatureLoadStatus.empty,
          }.contains(widget.snapshot.status);
    }

    try {
      if (!await read(FeatureQuery(date: date))) return;
      if (widget.snapshot.details.isEmpty) {
        _change(() {
          _libraries = [];
          _areas = [];
          _libraryId = _storeyId = _areaId = null;
          _clearAreaSelection();
        });
        return;
      }
      final libraries = _libraries
          .where(
            (item) =>
                item.id.trim().isNotEmpty &&
                _libraries.where((other) => other.id == item.id).length == 1,
          )
          .toList();
      if (libraries.isEmpty) return;
      final library =
          libraries.where((p) => p.id == _libraryId).firstOrNull ??
          libraries.first;
      final floors = library.storeys
          .where(
            (p) =>
                p.id.trim().isNotEmpty &&
                library.storeys.where((other) => other.id == p.id).length == 1,
          )
          .toList();
      final floor =
          floors
              .where((p) => library.id == _libraryId && p.id == _storeyId)
              .firstOrNull ??
          floors.firstOrNull;
      if (!await read(
        FeatureQuery(
          view: FeatureQueryView.libbookAreas,
          premisesId: library.id,
          storeyId: floor?.id,
          date: date,
        ),
      ))
        return;
      final areas = _areas
          .map((d) => d.presentation)
          .whereType<LibbookAreaPresentation>()
          .where(_validArea)
          .toList();
      if (areas.isEmpty) {
        _change(() {
          _areaId = null;
          _clearAreaSelection();
        });
        return;
      }
      final area =
          areas.where((p) => p.id == _areaId).firstOrNull ?? areas.first;
      if (!await read(
        FeatureQuery(
          view: FeatureQueryView.libbookAreaDetail,
          areaId: area.id,
          date: date,
        ),
      ))
        return;
      if (_selectedDay != null && _selectedSlot != null) await read(_seatDraft);
    } finally {
      if (mounted && identical(_refreshToken, token)) {
        _change(() => _refreshToken = null);
      }
    }
  }
}
