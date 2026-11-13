import 'package:flutter/material.dart';

/// 页面与分页内容切换的轻量过渡，以及左缘侧滑返回。
///
/// 内容由状态切换而不是路由，子树始终是同一个；[pageKey] 变化时整体淡入并横向
/// 滑入一小段。方向由 [order] 决定：变大（进入下一级、翻到后一周）从右侧，变小
/// （返回、翻到前一周）从左侧；[order] 不变或 [lane] 变化时只淡入。[onBack]
/// 不为空时，从左缘向右拖动内容跟手移动，超过三分之一宽度或快速甩动即返回。
class UiPageTransition extends StatefulWidget {
  const UiPageTransition({
    super.key,
    required this.pageKey,
    required this.order,
    required this.child,
    this.lane,
    this.onBack,
  });

  /// 当前页面的标识；同级切换（底栏分类）传相同的值，不播放过渡。
  final Object? pageKey;

  /// 当前页面在前后顺序中的位置：页面层级的深度，或周次、日期的序号。
  final int order;

  /// [order] 所属的序列（如视图类型、学期）；换了序列的两个位置不比较前后。
  final Object? lane;
  final VoidCallback? onBack;
  final Widget child;

  @override
  State<UiPageTransition> createState() => _UiPageTransitionState();
}

class _UiPageTransitionState extends State<UiPageTransition>
    with TickerProviderStateMixin {
  static const _edge = 24.0;
  static const _shift = 28.0;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  int _from = 1;
  double _drag = 0;
  double _settleFrom = 0;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      setState(() => _drag = _settleFrom * (1 - _settle.value));
    });
  }

  @override
  void didUpdateWidget(covariant UiPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageKey != widget.pageKey) {
      _settle.stop();
      _drag = 0;
      if (MediaQuery.disableAnimationsOf(context)) {
        _enter.value = 1;
        return;
      }
      _from = oldWidget.lane != widget.lane
          ? 0
          : widget.order.compareTo(oldWidget.order).sign;
      _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _settle.dispose();
    super.dispose();
  }

  void _end(DragEndDetails details, double width) {
    final back = widget.onBack;
    if (back != null &&
        (_drag > width / 3 || (details.primaryVelocity ?? 0) > 600)) {
      back();
      // 页面标识没有变化（如页面内部自行返回上一步）时回到原位。
      if (mounted && _drag != 0) _release();
      return;
    }
    _release();
  }

  void _release() {
    _settleFrom = _drag;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final content = AnimatedBuilder(
      animation: _enter,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_enter.value);
        return Opacity(
          opacity: _enter.isAnimating ? t.clamp(0.0, 1.0) : 1,
          child: Transform.translate(
            offset: Offset(_from * _shift * (1 - t) + _drag, 0),
            child: child,
          ),
        );
      },
      // 过渡只改变位置和透明度，正文的绘制结果可以跨动画帧复用。
      child: RepaintBoundary(child: widget.child),
    );
    // 内容始终处在同一层级：侧滑区域的有无不能让页面子树重建而丢失状态。
    final swipe = widget.onBack != null && !rtl;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(child: content),
          if (swipe)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _edge,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                excludeFromSemantics: true,
                onHorizontalDragStart: (_) => _settle.stop(),
                onHorizontalDragUpdate: (details) => setState(
                  () => _drag = (_drag + details.delta.dx).clamp(
                    0.0,
                    constraints.maxWidth,
                  ),
                ),
                onHorizontalDragEnd: (details) =>
                    _end(details, constraints.maxWidth),
                onHorizontalDragCancel: _release,
              ),
            ),
        ],
      ),
    );
  }
}
