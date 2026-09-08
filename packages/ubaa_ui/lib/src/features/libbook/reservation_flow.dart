part of '../../widgets.dart';

/// 单页保留旧版楼馆→楼层→分区→座位的顺序，缓存仅用于只读选择。
class _LibbookReservationFlow extends StatefulWidget {
  const _LibbookReservationFlow({
    required this.snapshot,
    required this.query,
    required this.cacheEpoch,
    required this.filter,
    required this.fallback,
    required this.onQuery,
    required this.onSeatQuery,
    this.onReserve,
  });
  final FeatureSnapshot snapshot;
  final FeatureQuery query;
  final int cacheEpoch;
  final String filter;
  final Widget fallback;
  final Future<void> Function(FeatureQuery)? onQuery;
  final void Function(FeatureQuery) onSeatQuery;
  final LibbookReserveStarter? onReserve;
  @override
  State<_LibbookReservationFlow> createState() =>
      _LibbookReservationFlowState();
}

class _LibbookReservationFlowState extends State<_LibbookReservationFlow> {
  List<LibbookLibraryPresentation> _libraries = [];
  List<FeatureDetail> _areas = [];
  String? _libraryId;
  String? _storeyId;
  String? _areaId;
  String? _day;
  String? _selectedSeat;
  FeatureSnapshot? _consumed;
  int? _afterRevision;
  bool _pending = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _consume();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) _consume();
  }

  @override
  void didUpdateWidget(covariant _LibbookReservationFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheEpoch != widget.cacheEpoch) {
      _clear();
      _afterRevision = oldWidget.snapshot.readContext?.requestRevision ?? -1;
    }
    final query = widget.query;
    final incomingDay = query.date == null ? null : _date(query.date!);
    if (_day != null && incomingDay != null && _day != incomingDay) _clear();
    if (!query.hasSameParameters(oldWidget.query)) _selectedSeat = null;
    _consume();
  }

  void _clear() {
    _generation++;
    _libraries = [];
    _areas = [];
    _libraryId = _storeyId = _areaId = _day = _selectedSeat = null;
    _consumed = null;
    _pending = false;
  }

  void _consume() {
    final snapshot = widget.snapshot;
    if (identical(_consumed, snapshot) ||
        !const {
          FeatureLoadStatus.success,
          FeatureLoadStatus.stale,
          FeatureLoadStatus.empty,
        }.contains(snapshot.status))
      return;
    if (_afterRevision != null &&
        (snapshot.readContext?.requestRevision ?? -1) <= _afterRevision!)
      return;
    _afterRevision = null;
    _consumed = snapshot;
    final details = snapshot.details;
    if (snapshot.status == FeatureLoadStatus.empty ||
        (widget.query.view == FeatureQueryView.libbookSeats &&
            !details.any(
              (d) =>
                  d.presentation is LibbookSeatPresentation &&
                  (d.presentation! as LibbookSeatPresentation).id ==
                      _selectedSeat,
            ))) {
      _selectedSeat = null;
    }
    if (details.isNotEmpty &&
        details.every((d) => d.presentation is LibbookLibraryPresentation)) {
      _libraries = details
          .map((d) => d.presentation! as LibbookLibraryPresentation)
          .toList();
      _day = _libraries.first.queryDate;
      final candidates = _libraries.where(
        (library) =>
            library.id.trim().isNotEmpty &&
            _libraries.where((other) => other.id == library.id).length == 1,
      );
      if (candidates.isNotEmpty) {
        final previous = candidates.where(
          (library) => library.id == _libraryId,
        );
        final next = previous.isEmpty ? candidates.first : previous.single;
        _schedule(() => _chooseLibrary(next));
      }
    } else if (widget.query.view == FeatureQueryView.libbookAreas) {
      _areas = details;
      _libraryId = widget.query.premisesId;
      _storeyId = widget.query.storeyId;
      if (widget.query.date case final date?) _day = _date(date);
      final candidates = details.where((d) {
        final p = d.presentation;
        return p is LibbookAreaPresentation &&
            p.id.trim().isNotEmpty &&
            p.premisesId == _libraryId &&
            (_storeyId == null || p.storeyId == _storeyId) &&
            details
                    .where(
                      (other) =>
                          other.presentation is LibbookAreaPresentation &&
                          (other.presentation! as LibbookAreaPresentation).id ==
                              p.id,
                    )
                    .length ==
                1;
      });
      if (candidates.isNotEmpty) {
        final previous = candidates.where(
          (d) => (d.presentation! as LibbookAreaPresentation).id == _areaId,
        );
        final p =
            (previous.isEmpty ? candidates.first : previous.single)
                    .presentation!
                as LibbookAreaPresentation;
        _schedule(() => _chooseArea(p));
      }
    } else if (widget.query.view == FeatureQueryView.libbookAreaDetail ||
        widget.query.view == FeatureQueryView.libbookSeats) {
      _areaId = widget.query.areaId;
    }
  }

  void _schedule(Future<void> Function() action) {
    final snapshot = widget.snapshot;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          generation != _generation ||
          !identical(snapshot, widget.snapshot))
        return;
      if (!TickerMode.valuesOf(context).enabled) {
        // 隐藏页面不扩展读取链；再次可见时按届时快照处理。
        _consumed = null;
        return;
      }
      action();
    });
  }

  Future<void> _read(FeatureQuery query) async {
    if (widget.onQuery == null) return;
    final generation = ++_generation;
    setState(() {
      _pending = true;
      _selectedSeat = null;
    });
    try {
      await widget.onQuery!(query);
    } finally {
      if (mounted && generation == _generation)
        setState(() => _pending = false);
    }
  }

  Future<void> _chooseLibrary(LibbookLibraryPresentation library) async {
    final date = _parsedDay(library.queryDate);
    if (date == null) return;
    final floors = library.storeys.where(
      (floor) =>
          floor.id.trim().isNotEmpty &&
          library.storeys.where((other) => other.id == floor.id).length == 1,
    );
    final previous = floors.where(
      (floor) => library.id == _libraryId && floor.id == _storeyId,
    );
    final floor = floors.isEmpty
        ? null
        : previous.isEmpty
        ? floors.first.id
        : previous.single.id;
    _libraryId = library.id;
    _storeyId = floor;
    _areaId = null;
    _areas = [];
    _day = library.queryDate;
    return _read(
      FeatureQuery(
        view: FeatureQueryView.libbookAreas,
        premisesId: library.id,
        storeyId: floor,
        date: date,
      ),
    );
  }

  Future<void> _chooseFloor(LibbookStoreyPresentation floor) async {
    final date = _parsedDay(_day ?? '');
    if (date == null || _libraryId == null) return;
    _storeyId = floor.id;
    _areaId = null;
    _areas = [];
    return _read(
      FeatureQuery(
        view: FeatureQueryView.libbookAreas,
        premisesId: _libraryId,
        storeyId: floor.id,
        date: date,
      ),
    );
  }

  Future<void> _chooseArea(LibbookAreaPresentation area) async {
    final date = _parsedDay(area.queryDate);
    if (date == null) return;
    _areaId = area.id;
    return _read(
      FeatureQuery(
        view: FeatureQueryView.libbookAreaDetail,
        areaId: area.id,
        date: date,
      ),
    );
  }

  void _toggleSeat(String id) =>
      setState(() => _selectedSeat = _selectedSeat == id ? null : id);

  DateTime? _parsedDay(String value) {
    final date = DateTime.tryParse(value);
    return date != null && _date(date) == value ? date : null;
  }

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool get _busy =>
      _pending || widget.snapshot.status == FeatureLoadStatus.loading;
  bool _matchesDetail(FeatureDetail detail, Iterable<String> extra) => _matches(
    [
      detail.title,
      detail.subtitle ?? '',
      for (final field in detail.fields) ...[field.label, field.value],
      ...extra,
    ].join(' '),
  );
  bool _matches(String value) =>
      value.toLowerCase().contains(widget.filter.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final details = widget.snapshot.details;
    final typed =
        details.isNotEmpty &&
        details.every(
          (d) => switch (d.presentation) {
            LibbookLibraryPresentation() ||
            LibbookAreaPresentation() ||
            LibbookAreaDetailPresentation() ||
            LibbookSeatPresentation() => true,
            _ => false,
          },
        );
    if (!typed && _libraries.isEmpty && _areas.isEmpty) return widget.fallback;
    // 混合或未知结构仍沿通用白名单展示，不丢条目或误授操作。
    if (details.isNotEmpty && !typed) return widget.fallback;
    final selectedLibraries = _libraries.where(
      (library) => library.id == _libraryId,
    );
    final library = selectedLibraries.length == 1
        ? selectedLibraries.single
        : null;
    final mapAreas = <String, String>{
      for (final detail in details)
        if (detail.presentation case LibbookAreaDetailPresentation p)
          p.id: p.name,
      for (final detail in details)
        if (detail.presentation case LibbookSeatPresentation p)
          p.areaId: '座位分布',
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        if (_libraries.isNotEmpty) ...[
          _section('楼馆'),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final library in _libraries)
                FilterChip(
                  label: Text(
                    '${library.name} ${library.freeNum}/${library.totalNum}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: library.id == _libraryId,
                  onSelected:
                      _busy ||
                          library.id.trim().isEmpty ||
                          _libraries.where((p) => p.id == library.id).length !=
                              1
                      ? null
                      : (_) => _chooseLibrary(library),
                ),
            ],
          ),
        ],
        if (library != null && library.storeys.isNotEmpty) ...[
          _section('楼层'),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final floor in library.storeys)
                FilterChip(
                  label: Text(
                    '${floor.name} ${floor.freeNum}/${floor.totalNum}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: floor.id == _storeyId,
                  onSelected:
                      _busy ||
                          floor.id.trim().isEmpty ||
                          library.storeys
                                  .where((p) => p.id == floor.id)
                                  .length !=
                              1
                      ? null
                      : (_) => _chooseFloor(floor),
                ),
            ],
          ),
        ],
        if (_day != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_day!, style: Theme.of(context).textTheme.bodySmall),
          ),
        if (_areas.isNotEmpty) ...[
          _section('分区'),
          for (final detail in _areas)
            if (detail.presentation case LibbookAreaPresentation p
                when _matchesDetail(detail, [
                  p.name,
                  p.areaName,
                  p.id,
                  p.premisesId,
                  p.storeyId,
                  p.queryDate,
                ]))
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(p.name),
                  subtitle: Text(
                    '${p.areaName} · 空闲 ${p.freeNum}/${p.totalNum}',
                  ),
                  selected: p.id == _areaId,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || p.id.trim().isEmpty
                      ? null
                      : () => _chooseArea(p),
                ),
              ),
        ],
        if (!_busy && mapAreas.length == 1)
          _LibraryMapControl(
            areaId: mapAreas.keys.single,
            areaName: mapAreas.values.single,
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (widget.snapshot.error case final error? when !_busy)
          FriendlyErrorCard(error: error, onRetry: () => _read(widget.query)),
        if (!_busy && widget.snapshot.status == FeatureLoadStatus.stale)
          const Text('以下为上次成功加载的数据。'),
        if (!_busy &&
            details.isEmpty &&
            widget.snapshot.status == FeatureLoadStatus.empty)
          const Padding(padding: EdgeInsets.all(16), child: Text('暂无可显示的结果')),
        if (!_busy)
          for (final detail in details)
            if (detail.presentation case LibbookAreaDetailPresentation p
                when _matchesDetail(detail, [
                  p.id,
                  p.name,
                  ...p.availableDates,
                  for (final slot in p.timeSlots) ...[
                    slot.id,
                    slot.label,
                    slot.start,
                    slot.end,
                  ],
                ]))
              _areaDetail(context, p),
        if (!_busy &&
            details.any((d) => d.presentation is LibbookSeatPresentation))
          _seatGrid(context, details),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 6),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}
