part of '../../widgets.dart';

// 冻结LibBookReserveScreen的资源白名单；不以相似编号推断另一张地图。
const _libraryMapIds = {
  '6',
  '8',
  '16',
  '18',
  '19',
  '20',
  '21',
  '22',
  '23',
  '24',
  '25',
  '26',
  '27',
  '28',
  '29',
  '52',
  '53',
  '63',
  '64',
  '65',
  '67',
  '68',
  '69',
  '71',
  '72',
  '73',
  '82',
  '83',
  '117',
};

class _LibraryMapControl extends StatelessWidget {
  const _LibraryMapControl({required this.areaId, required this.areaName});
  final String areaId;
  final String areaName;
  @override
  Widget build(BuildContext context) {
    final available = _libraryMapIds.contains(areaId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: !available
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        _LibraryAreaMap(areaId: areaId, areaName: areaName),
                  ),
            icon: const Icon(Icons.map_outlined),
            label: const Text('查看座位分布'),
          ),
          if (!available)
            Text('当前分区暂无平面图', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _LibraryAreaMap extends StatefulWidget {
  const _LibraryAreaMap({required this.areaId, required this.areaName});
  final String areaId;
  final String areaName;
  @override
  State<_LibraryAreaMap> createState() => _LibraryAreaMapState();
}

class _LibraryAreaMapState extends State<_LibraryAreaMap> {
  final _transform = TransformationController();
  Size _viewport = Size.zero;
  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _reset() => _transform.value = Matrix4.identity();
  void _zoom(double factor) {
    final scale = (_transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      5.0,
    );
    if (scale <= 1) {
      _reset();
      return;
    }
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setEntry(0, 3, _viewport.width * (1 - scale) / 2)
      ..setEntry(1, 3, _viewport.height * (1 - scale) / 2);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.areaName.isEmpty ? '座位分布' : widget.areaName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '缩小',
                onPressed: () => _zoom(0.5),
                icon: const Icon(Icons.zoom_out),
              ),
              IconButton(
                tooltip: '放大',
                onPressed: () => _zoom(2),
                icon: const Icon(Icons.zoom_in),
              ),
              TextButton(onPressed: _reset, child: const Text('重置')),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            '静态座位分布图，颜色不代表当前可用状态。请在预约页面选择座位。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport = constraints.biggest;
                return ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: 5,
                    trackpadScrollCausesScale: true,
                    onInteractionEnd: (_) {
                      if (_transform.value.getMaxScaleOnAxis() <= 1.001)
                        _reset();
                    },
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: Image.asset(
                        'assets/libbook_maps/area_${widget.areaId}.png',
                        package: 'ubaa_ui',
                        fit: BoxFit.contain,
                        semanticLabel: '静态座位分布图',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
