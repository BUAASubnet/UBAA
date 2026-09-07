part of '../widgets.dart';

class _ClassroomContent extends StatefulWidget {
  const _ClassroomContent({required this.details, required this.wide});
  final List<FeatureDetail> details;
  final bool wide;
  @override
  State<_ClassroomContent> createState() => _ClassroomContentState();
}

class _ClassroomContentState extends State<_ClassroomContent> {
  String? _floor;

  @override
  void didUpdateWidget(covariant _ClassroomContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final floors = widget.details.map(
      (d) => (d.presentation! as ClassroomPresentation).floorId,
    );
    if (!floors.contains(_floor) ||
        _source(oldWidget.details) != _source(widget.details))
      _floor = null;
  }

  @override
  Widget build(BuildContext context) {
    final floors = <String, (String, List<FeatureDetail>)>{};
    for (final detail in widget.details) {
      final room = detail.presentation! as ClassroomPresentation;
      (floors
              .putIfAbsent(
                room.floorId,
                () => (room.floorName, <FeatureDetail>[]),
              )
              .$2)
          .add(detail);
    }
    final selected = _floor == null
        ? floors.entries
        : floors.entries.where((f) => f.key == _floor);
    Widget results = LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in selected) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                group.value.$1,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final detail in group.value.$2)
                  SizedBox(
                    width: constraints.maxWidth >= 640
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth,
                    child: _AcademicCard(detail: detail),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
    final source = _source(widget.details);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (source.$1 != null && source.$2 != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('查询日期 ${source.$1} · 校区 ${source.$2}'),
          ),
        if (!widget.wide)
          results
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 180,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('当前页楼层'),
                      ),
                      ListTile(
                        title: const Text('全部（本页）'),
                        selected: _floor == null,
                        onTap: () => setState(() => _floor = null),
                      ),
                      for (final group in floors.entries)
                        ListTile(
                          title: Text(group.value.$1),
                          selected: _floor == group.key,
                          onTap: () => setState(() => _floor = group.key),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(child: results),
            ],
          ),
      ],
    );
  }

  (String?, int?) _source(List<FeatureDetail> details) {
    if (details.isEmpty) return (null, null);
    final first = details.first.presentation! as ClassroomPresentation;
    if (!details.every(
      (d) =>
          d.presentation is ClassroomPresentation &&
          (d.presentation! as ClassroomPresentation).queryDate ==
              first.queryDate &&
          (d.presentation! as ClassroomPresentation).campus == first.campus,
    ))
      return (null, null);
    return (first.queryDate, first.campus);
  }
}
