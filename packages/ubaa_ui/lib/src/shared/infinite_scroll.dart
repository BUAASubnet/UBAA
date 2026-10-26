import 'dart:async';
import 'package:flutter/material.dart';
import 'loading.dart' show LoadingGlyph;

/// 在主列表接近底部时续载，忽略嵌套文本、横向表格和后台导航页。
class InfiniteScroll extends StatefulWidget {
  const InfiniteScroll({
    super.key,
    required this.child,
    this.onLoadMore,
    this.loading = false,
    this.error,
    this.hasMore = false,
  });
  final Widget child;
  final Future<void> Function()? onLoadMore;
  final bool loading, hasMore;
  final String? error;
  @override
  State<InfiniteScroll> createState() => _InfiniteScrollState();
}

class _InfiniteScrollState extends State<InfiniteScroll> {
  bool _scheduled = false;
  ScrollMetrics? _metrics;

  void _consider(ScrollMetrics metrics) {
    _metrics = metrics;
    if (_scheduled ||
        metrics.axis != Axis.vertical ||
        metrics.extentAfter > 240 ||
        widget.loading ||
        widget.error != null ||
        !widget.hasMore ||
        widget.onLoadMore == null ||
        !TickerMode.valuesOf(context).enabled)
      return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          widget.loading ||
          widget.error != null ||
          !widget.hasMore ||
          !TickerMode.valuesOf(context).enabled ||
          (_metrics?.extentAfter ?? 999) > 240)
        return;
      unawaited(widget.onLoadMore?.call());
    });
  }

  @override
  void didUpdateWidget(covariant InfiniteScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新页可能全部被本地筛选隐藏；仍允许继续查找后续匹配项。
    if (oldWidget.loading && !widget.loading && _metrics != null)
      _consider(_metrics!);
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _consider(notification.metrics);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _consider(notification.metrics);
            return false;
          },
          child: Column(
            children: [
              Expanded(child: widget.child),
              if (widget.loading)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LoadingGlyph(),
                      SizedBox(width: 8),
                      Text('正在加载更多…'),
                    ],
                  ),
                )
              else if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(widget.error!),
                      TextButton(
                        onPressed: widget.onLoadMore,
                        child: const Text('重试加载'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}
