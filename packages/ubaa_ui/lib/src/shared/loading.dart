import 'package:flutter/material.dart';

/// 小范围进度占用固定尺寸，不为状态切换增加一行。
class LoadingGlyph extends StatelessWidget {
  const LoadingGlyph({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 20,
    child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: '正在加载'),
  );
}

/// 初次读取的静态骨架只占内容区，避免持续闪动和重复说明。
class LoadingPlaceholder extends StatelessWidget {
  const LoadingPlaceholder({this.cards = 3, super.key});
  final int cards;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在加载',
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < cards; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _line(context, .48, 20),
                    const SizedBox(height: 12),
                    _line(context, .8, 14),
                    const SizedBox(height: 8),
                    _line(context, .6, 14),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _line(BuildContext context, double width, double height) =>
      FractionallySizedBox(
        widthFactor: width,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}

/// 刷新期间保留按钮位置并禁止重复触发，不改变内容布局。
class RefreshActionButton extends StatefulWidget {
  const RefreshActionButton({
    required this.onRefresh,
    required this.tooltip,
    super.key,
  });
  final Future<void> Function() onRefresh;
  final String tooltip;
  @override
  State<RefreshActionButton> createState() => _RefreshActionButtonState();
}

class _RefreshActionButtonState extends State<RefreshActionButton> {
  bool _busy = false;
  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: widget.tooltip,
    onPressed: _busy ? null : _refresh,
    icon: _busy ? const LoadingGlyph() : const Icon(Icons.refresh),
  );
}
