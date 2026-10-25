import 'package:flutter/material.dart';

/// 接收最外层纵向滚动；横向表格和内嵌列表不触发整页刷新。
class PullToRefresh extends StatelessWidget {
  const PullToRefresh({
    required this.onRefresh,
    required this.child,
    this.enabled = true,
    super.key,
  });
  final Future<void> Function() onRefresh;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final behavior = ScrollConfiguration.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      notificationPredicate: (notification) {
        if (!enabled || notification.metrics.axis != Axis.vertical)
          return false;
        var vertical = 0;
        notification.context?.visitAncestorElements((element) {
          if (identical(element, context)) return false;
          if (element.widget case Scrollable scrollable
              when axisDirectionToAxis(scrollable.axisDirection) ==
                  Axis.vertical) {
            vertical++;
          }
          return vertical < 2;
        });
        return vertical <= 1;
      },
      child: ScrollConfiguration(
        behavior: behavior.copyWith(
          physics: AlwaysScrollableScrollPhysics(
            parent: behavior.getScrollPhysics(context),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// 空内容和错误仍占满正文，并提供可下拉的纵向滚动区域。
class RefreshViewport extends StatelessWidget {
  const RefreshViewport({required this.child, super.key});
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
  );
}
