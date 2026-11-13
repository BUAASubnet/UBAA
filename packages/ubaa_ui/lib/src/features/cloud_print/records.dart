part of 'view.dart';

class _Stations extends StatefulWidget {
  const _Stations({required this.service});
  final CloudPrintService service;

  @override
  State<_Stations> createState() => _StationsState();
}

class _StationsState extends State<_Stations> {
  late Future<List<PrintStation>> _read = widget.service.stations();
  void _reload() => setState(() => _read = widget.service.stations());

  @override
  Widget build(BuildContext context) => _Load(
    read: _read,
    retry: _reload,
    body: (List<PrintStation> stations) {
      final groups = <String, List<PrintStation>>{};
      for (final station in stations) {
        groups.putIfAbsent(station.group ?? '其他打印点', () => []).add(station);
      }
      return ListView(
        padding: UbaaTheme.pageInsets(context),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('设备状态'),
            trailing: IconButton(
              tooltip: '刷新打印点',
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
          ),
          if (stations.isEmpty) const ListTile(title: Text('暂无可显示的打印点')),
          for (final group in groups.entries) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                group.key,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final station in group.value)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.print_outlined),
                title: Text(station.name),
                subtitle: Text(
                  [
                    station.state,
                    if (station.papers.isNotEmpty) station.papers.join(' / '),
                    if (station.capabilities.isNotEmpty)
                      station.capabilities.join('、'),
                  ].join(' · '),
                ),
              ),
          ],
        ],
      );
    },
  );
}

class _Records extends StatefulWidget {
  const _Records({required this.service});
  final CloudPrintService service;

  @override
  State<_Records> createState() => _RecordsState();
}

class _RecordsState extends State<_Records> {
  late DateTimeRange _range = _initialRange();
  PrintRecordKind _kind = PrintRecordKind.print;
  int _page = 1;
  late Future<PrintRecords> _read = _load();

  DateTimeRange _initialRange() {
    final now = uiCampusNow();
    return DateTimeRange(
      start: DateTime(now.year, now.month, now.day - 29),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  Future<PrintRecords> _load() =>
      widget.service.records(_range.start, _range.end, _kind, _page);
  void _go(int page) => setState(() {
    _page = page;
    _read = _load();
  });

  Future<void> _chooseDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: _initialRange().end,
      initialDateRange: _range,
    );
    if (range == null || !mounted) return;
    _range = range;
    _go(1);
  }

  String _short(DateTime date) =>
      MaterialLocalizations.of(context).formatCompactDate(date);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: UbaaTheme.pageInsets(context, top: 8, bottom: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _chooseDates,
              icon: const Icon(Icons.date_range_outlined),
              label: Text('${_short(_range.start)} – ${_short(_range.end)}'),
            ),
            for (final (kind, label) in [
              (PrintRecordKind.print, '打印'),
              (PrintRecordKind.copy, '复印'),
              (PrintRecordKind.scan, '扫描'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _kind == kind,
                onSelected: (_) {
                  _kind = kind;
                  _go(1);
                },
              ),
          ],
        ),
      ),
      Expanded(
        child: _Load(
          read: _read,
          retry: () => _go(_page),
          body: (PrintRecords result) => result.items.isEmpty
              ? const Center(child: Text('该日期范围内没有记录'))
              : ListView(
                  padding: UbaaTheme.pageInsets(context, top: 0),
                  children: [
                    for (final record in result.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_dateTime(record.date, record.time)),
                        subtitle: Text(
                          [
                            '${record.pages} 页',
                            if (record.paper != null) record.paper!,
                            '免费额度 ${_yuan(record.freeCents)}',
                            '校园卡 ${_yuan(record.cardCents)}',
                            '其他 ${_yuan(record.otherCents)}',
                            '合计 ${_yuan(record.freeCents + record.cardCents + record.otherCents)}',
                          ].join(' · '),
                        ),
                      ),
                    Center(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          IconButton(
                            tooltip: '上一页',
                            onPressed: _page > 1 ? () => _go(_page - 1) : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Text('第 $_page / ${result.totalPages} 页'),
                          IconButton(
                            tooltip: '下一页',
                            onPressed: _page < result.totalPages
                                ? () => _go(_page + 1)
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    ],
  );

  String _yuan(int cents) => '¥${(cents / 100).toStringAsFixed(2)}';
}
