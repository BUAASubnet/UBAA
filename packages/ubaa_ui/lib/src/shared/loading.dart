import 'package:flutter/material.dart';

/// 小范围进度占用固定尺寸，不为状态切换增加一行。
class LoadingGlyph extends StatelessWidget {
  const LoadingGlyph({this.dimension = 20, super.key});
  final double dimension;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: dimension,
    child: const CircularProgressIndicator(
      strokeWidth: 2,
      semanticsLabel: '正在加载',
    ),
  );
}

/// 首次读取在内容区居中；卡片和列表内的局部读取使用固定高度。
class LoadingPlaceholder extends StatelessWidget {
  const LoadingPlaceholder({this.compact = false, super.key});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    const indicator = Center(child: LoadingGlyph(dimension: 32));
    return compact ? const SizedBox(height: 120, child: indicator) : indicator;
  }
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
