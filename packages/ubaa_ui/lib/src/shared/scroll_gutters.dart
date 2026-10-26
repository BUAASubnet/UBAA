import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 保留正文限宽，让两侧留白的滚轮操作驱动当前页面的主纵向滚动。
class ScrollGutters extends StatefulWidget {
  const ScrollGutters({required this.maxWidth, required this.child, super.key});

  final double maxWidth;
  final Widget child;

  @override
  State<ScrollGutters> createState() => _ScrollGuttersState();
}

class _ScrollGuttersState extends State<ScrollGutters> {
  final _contentKey = GlobalKey();

  ScrollableState? _visibleScroll() {
    ScrollableState? target;
    void visit(Element element) {
      if (target != null) return;
      // IndexedStack 保留的页面和导航父帧不能接收当前页的滚轮操作。
      final widget = element.widget;
      if (widget is Offstage && widget.offstage ||
          widget is Visibility && !widget.visible ||
          widget is TickerMode && !widget.enabled) {
        return;
      }
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        if (state.widget.axis == Axis.vertical) {
          target = state;
          return;
        }
      }
      element.visitChildren(visit);
    }

    // 找到主滚动就停止，不遍历列表条目或接管内嵌滚动区域。
    _contentKey.currentContext?.visitChildElements(visit);
    return target;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    final box = _contentKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final point = box.globalToLocal(event.position);
    if (point.dx >= 0 && point.dx < box.size.width) return;
    final scroll = _visibleScroll();
    if (scroll == null) return;
    final position = scroll.position;
    if (event is PointerScrollInertiaCancelEvent) {
      position.pointerScroll(0);
      return;
    }
    if (event is! PointerScrollEvent ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return;
    }
    final behavior =
        scroll.widget.scrollBehavior ?? ScrollConfiguration.of(scroll.context);
    final flipAxes =
        event.kind == PointerDeviceKind.mouse &&
        HardwareKeyboard.instance.logicalKeysPressed.any(
          behavior.pointerAxisModifiers.contains,
        );
    var delta = flipAxes ? event.scrollDelta.dx : event.scrollDelta.dy;
    if (axisDirectionIsReversed(scroll.widget.axisDirection)) delta = -delta;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (delta == 0 || next == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (scroll.mounted) position.pointerScroll(delta);
    });
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerSignal: _onPointerSignal,
    child: Center(
      child: ConstrainedBox(
        key: _contentKey,
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: widget.child,
      ),
    ),
  );
}
