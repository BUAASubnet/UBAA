part of '../../widgets.dart';

extension _LibbookReservationChoices on _LibbookReservationFlowState {
  Widget buildChoices(BuildContext context) {
    final libraries = _libraries
        .where(
          (item) =>
              item.id.trim().isNotEmpty &&
              _libraries.where((other) => other.id == item.id).length == 1,
        )
        .toList();
    final selected = libraries.where((item) => item.id == _libraryId);
    final library = selected.length == 1 ? selected.single : null;
    final floors = library?.storeys ?? const <LibbookStoreyPresentation>[];
    final areas = _areas
        .map((d) => d.presentation)
        .whereType<LibbookAreaPresentation>()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (libraries.isNotEmpty)
          _libraryChoice(
            '楼馆',
            _libraryId,
            {
              for (final item in libraries)
                item.id: '${item.name} ${item.freeNum}/${item.totalNum}',
            },
            (id) => unawaited(
              _chooseLibrary(libraries.singleWhere((p) => p.id == id)),
            ),
          ),
        if (floors.isNotEmpty)
          _libraryChoice(
            '楼层',
            _storeyId,
            {
              for (final floor in floors)
                if (floor.id.trim().isNotEmpty &&
                    floors.where((other) => other.id == floor.id).length == 1)
                  floor.id: '${floor.name} ${floor.freeNum}/${floor.totalNum}',
            },
            (id) =>
                unawaited(_chooseFloor(floors.singleWhere((p) => p.id == id))),
          ),
        if (areas.isNotEmpty)
          _libraryChoice(
            '分区',
            _areaId,
            {
              for (final area in areas)
                if (area.id.trim().isNotEmpty &&
                    areas.where((other) => other.id == area.id).length == 1)
                  area.id:
                      '${area.name} · ${area.areaName} · 空闲 ${area.freeNum}/${area.totalNum}',
            },
            (id) =>
                unawaited(_chooseArea(areas.singleWhere((p) => p.id == id))),
          ),
        if (_areaOptions case final area? when !_busy)
          _areaDetail(context, area),
      ],
    );
  }

  Widget _libraryChoice(
    String label,
    String? selected,
    Map<String, String> choices,
    ValueChanged<String> select,
  ) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, isDense: true),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey('libbook-choice-$label'),
          value: choices.containsKey(selected) ? selected : null,
          isExpanded: true,
          isDense: true,
          itemHeight: null,
          selectedItemBuilder: (_) => [
            for (final text in choices.values)
              Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          items: [
            for (final entry in choices.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(entry.value),
                ),
              ),
          ],
          onChanged: _busy || widget.onQuery == null
              ? null
              : (value) {
                  if (value != null) select(value);
                },
        ),
      ),
    ),
  );
}
