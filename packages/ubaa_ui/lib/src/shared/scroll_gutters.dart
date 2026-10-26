import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 保留正文限宽，让两侧留白的滚轮和触摸板操作驱动当前页面的主纵向滚动。
class ScrollGutters extends StatefulWidget {
  const ScrollGutters({required this.maxWidth, required this.child, super.key});

  final double maxWidth;
  final Widget child;

  @override
  State<ScrollGutters> createState() => _ScrollGuttersState();
}

class _ScrollGuttersState extends State<ScrollGutters> {
  final _contentKey = GlobalKey();
  late final VerticalDragGestureRecognizer _trackpad;
  ScrollableState? _dragScroll;
  ScrollHoldController? _hold;
  Drag? _drag;

  @override
  void initState() {
    super.initState();
    _trackpad =
        VerticalDragGestureRecognizer(
            supportedDevices: const {PointerDeviceKind.trackpad},
          )
          ..onDown = (_) {
            _hold = _dragPosition?.hold(() => _hold = null);
          }
          ..onStart = (details) {
            final position = _dragPosition;
            if (position == null) {
              _cancelDrag();
              return;
            }
            _drag = position.drag(details, () => _drag = null);
            _hold = null;
          }
          ..onUpdate = (details) {
            if (_dragPosition == null) {
              _cancelDrag();
            } else {
              _drag?.update(details);
            }
          }
          ..onEnd = (details) {
            if (_dragPosition == null) {
              _cancelDrag();
            } else {
              _drag?.end(details);
              _dragScroll = null;
            }
          }
          ..onCancel = _cancelDrag;
  }

  ScrollPosition? get _dragPosition {
    final scroll = _dragScroll;
    if (scroll == null ||
        !scroll.mounted ||
        !identical(scroll, _visibleScroll())) {
      return null;
    }
    return scroll.position;
  }

  void _cancelDrag() {
    _hold?.cancel();
    _drag?.cancel();
    _dragScroll = null;
  }

  @override
  void dispose() {
    _cancelDrag();
    _trackpad.dispose();
    super.dispose();
  }

  bool _isGutter(Offset globalPosition) {
    final box = _contentKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final point = box.globalToLocal(globalPosition);
    return point.dx < 0 || point.dx >= box.size.width;
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    if (!_isGutter(event.position)) return;
    final scroll = _visibleScroll();
    if (scroll == null ||
        !scroll.position.physics.shouldAcceptUserOffset(scroll.position)) {
      return;
    }
    final behavior =
        scroll.widget.scrollBehavior ?? ScrollConfiguration.of(scroll.context);
    if (!behavior.dragDevices.contains(PointerDeviceKind.trackpad)) return;
    _cancelDrag();
    _dragScroll = scroll;
    final physics = scroll.position.physics;
    // 复用正文的拖动、速度估算和惯性规则；不把触摸板更新转换成滚轮跳转。
    _trackpad
      ..minFlingDistance = physics.minFlingDistance
      ..minFlingVelocity = physics.minFlingVelocity
      ..maxFlingVelocity = physics.maxFlingVelocity
      ..velocityTrackerBuilder = behavior.velocityTrackerBuilder(scroll.context)
      ..dragStartBehavior = scroll.widget.dragStartBehavior
      ..multitouchDragStrategy = behavior.getMultitouchDragStrategy(
        scroll.context,
      )
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(scroll.context)
      ..addPointerPanZoom(event);
  }

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
    if (!_isGutter(event.position)) return;
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
    onPointerPanZoomStart: _onPanZoomStart,
    child: Center(
      child: ConstrainedBox(
        key: _contentKey,
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: widget.child,
      ),
    ),
  );
}
