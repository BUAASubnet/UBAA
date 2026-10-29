part of 'reservation_flow.dart';

extension LibbookReservationChoices on LibbookReservationFlowState {
  /// 楼馆即校区，切换很少，放到顶栏右上角。
  void publishLibraryPicker(BuildContext context) {
    final libraries = _libraries
        .where(
          (item) =>
              item.id.trim().isNotEmpty &&
              _libraries.where((other) => other.id == item.id).length == 1,
        )
        .toList();
    UiAppBarSlot.publish(
      context,
      FeatureId.libbook,
      libraries.isEmpty
          ? null
          : UiAppBarPicker<String>(
              key: const ValueKey('libbook-library'),
              tooltip: '切换楼馆',
              value: _libraryId,
              options: [
                for (final item in libraries)
                  (item.id, uiLibraryShortName(item.name)),
              ],
              onSelected: _busy || widget.onQuery == null
                  ? null
                  : (id) => unawaited(
                      _chooseLibrary(libraries.singleWhere((p) => p.id == id)),
                    ),
            ),
    );
  }

  Widget buildInlineChips(BuildContext context) {
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
        .where(_validArea)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (floors.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                for (final floor in floors)
                  if (floor.id.trim().isNotEmpty &&
                      floors.where((other) => other.id == floor.id).length == 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(
                          '${floor.name} · 空 ${floor.freeNum}/${floor.totalNum}',
                        ),
                        selected: floor.id == _storeyId,
                        onSelected: _busy || widget.onQuery == null
                            ? null
                            : (_) => unawaited(_chooseFloor(floor)),
                      ),
                    ),
              ],
            ),
          ),
        if (areas.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                for (final area in areas)
                  if (area.id.trim().isNotEmpty &&
                      areas.where((other) => other.id == area.id).length == 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(
                          '${area.name} · 空 ${area.freeNum}/${area.totalNum}',
                        ),
                        selected: area.id == _areaId,
                        onSelected: _busy || widget.onQuery == null
                            ? null
                            : (_) => unawaited(_chooseArea(area)),
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }

  /// 可左右滑动的一行选项；替代下拉框。
  Widget _chipRow(
    String label,
    String? selected,
    Map<String, String> choices,
    ValueChanged<String> select,
  ) => SingleChildScrollView(
    key: ValueKey('libbook-choice-$label'),
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        for (final entry in choices.entries)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(entry.value),
              selected: entry.key == selected,
              onSelected: _busy || widget.onQuery == null
                  ? null
                  : (_) => select(entry.key),
            ),
          ),
      ],
    ),
  );
}

/// “学院路校区图书馆”→“学院路”，顶栏只放得下短名。
String uiLibraryShortName(String name) {
  final short = name
      .trim()
      .replaceAll(RegExp(r'(校区)?图书馆$'), '')
      .replaceAll(RegExp(r'校区$'), '')
      .trim();
  return short.isEmpty ? name.trim() : short;
}
