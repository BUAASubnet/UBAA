import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;

/// 创建按钮距页面右下角的统一边距。
const ubaaCreateButtonMargin = 16.0;

/// 全应用统一的创建按钮：右下角圆形加号，含义放在 tooltip 与无障碍标签里。
///
/// [open] 用于展开菜单的场景（0 收起、1 展开），加号随之旋转成关闭。
/// [key] 直接落在 [FloatingActionButton] 上，便于定位与读取状态。
Widget ubaaCreateButton({
  Key? key,
  required String tooltip,
  required VoidCallback? onPressed,
  Animation<double>? open,
}) {
  const icon = Icon(Icons.add);
  return _CreateButtonPresence(
    child: Builder(
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        final enabled = onPressed != null;
        return FloatingActionButton(
          key: key,
          heroTag: null,
          tooltip: tooltip,
          onPressed: onPressed,
          // Material 的 FAB 不可用时外观不变；降低对比，避免看起来仍可点。
          backgroundColor: enabled ? null : colors.surfaceContainerHighest,
          foregroundColor: enabled
              ? null
              : colors.onSurface.withValues(alpha: .38),
          elevation: enabled ? null : 0,
          child: open == null
              ? icon
              : RotationTransition(
                  turns: Tween(begin: 0.0, end: .125).animate(open),
                  child: icon,
                ),
        );
      },
    ),
  );
}

/// 在页面 [Stack] 中按统一位置放置创建按钮。
Widget ubaaPositionedCreateButton({
  Key? key,
  required String tooltip,
  required VoidCallback? onPressed,
}) => Positioned(
  right: ubaaCreateButtonMargin,
  bottom: ubaaCreateButtonMargin,
  child: ubaaCreateButton(key: key, tooltip: tooltip, onPressed: onPressed),
);

/// 让外层 [Scaffold] 知道页面里的创建按钮。
///
/// 创建按钮叠在页面的 [Stack] 里，Scaffold 看不到它，浮动提示会照常贴底把它盖住。
/// 当前有可见的创建按钮时，[builder] 收到一个与按钮同尺寸的透明占位；把它放进
/// [Scaffold.floatingActionButton]（默认 endFloat 与页面按钮位置重合），提示就会
/// 像对待真按钮一样排在它上方，切换页面时也随之调整。没有可见按钮时收到 null。
class UiCreateButtonHost extends StatefulWidget {
  const UiCreateButtonHost({super.key, required this.builder});

  final Widget Function(BuildContext context, Widget? floatingActionButton)
  builder;

  @override
  State<UiCreateButtonHost> createState() => _UiCreateButtonHostState();
}

class _UiCreateButtonHostState extends State<UiCreateButtonHost> {
  final _visible = <Object>{};
  bool _present = false;
  bool _scheduled = false;

  // 按钮在构建或卸载阶段上报，此时不能重建外壳，一律留到帧末再统一刷新。
  // 调度器空闲也不能直接刷新：冷启动时 runApp 在帧外挂载根组件，同样处于构建中。
  void _report(Object button, {required bool visible}) {
    final changed = visible ? _visible.add(button) : _visible.remove(button);
    if (!changed || _scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _scheduled = false;
        _sync();
      })
      // 帧外或帧回调阶段上报时，回调要等下一帧才执行，确保下一帧会到来。
      ..ensureVisualUpdate();
  }

  void _sync() {
    if (!mounted || _present == _visible.isNotEmpty) return;
    setState(() => _present = _visible.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) => _CreateButtonHostScope(
    host: this,
    child: widget.builder(
      context,
      _present ? const _CreateButtonFootprint() : null,
    ),
  );
}

class _CreateButtonHostScope extends InheritedWidget {
  const _CreateButtonHostScope({required this.host, required super.child});
  final _UiCreateButtonHostState host;

  @override
  bool updateShouldNotify(_CreateButtonHostScope oldWidget) =>
      host != oldWidget.host;
}

/// 与创建按钮同尺寸的占位：不绘制、不接收点击、不进入语义树。
class _CreateButtonFootprint extends StatelessWidget {
  const _CreateButtonFootprint();

  // 与 [FloatingActionButton] 常规尺寸一致。
  static const _size = 56.0;

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: ExcludeSemantics(child: SizedBox.square(dimension: _size)),
  );
}

/// 向最近的 [UiCreateButtonHost] 上报按钮是否可见。
///
/// 外壳把已访问但未显示的页面留在 [IndexedStack] 里并关闭 [TickerMode]，
/// 被不透明路由盖住的页面也会关闭 [TickerMode]，这两种情况都按不可见处理。
class _CreateButtonPresence extends StatefulWidget {
  const _CreateButtonPresence({required this.child});
  final Widget child;

  @override
  State<_CreateButtonPresence> createState() => _CreateButtonPresenceState();
}

class _CreateButtonPresenceState extends State<_CreateButtonPresence> {
  _UiCreateButtonHostState? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final host = context
        .dependOnInheritedWidgetOfExactType<_CreateButtonHostScope>()
        ?.host;
    if (host != _host) {
      _host?._report(this, visible: false);
      _host = host;
    }
    _host?._report(this, visible: TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _host?._report(this, visible: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
