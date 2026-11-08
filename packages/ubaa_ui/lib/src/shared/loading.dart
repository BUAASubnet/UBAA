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

/// 页面忙碌登记表：标题栏右上角据此显示“更新中”。外壳销毁后的迟到登记直接忽略。
class UiBusyRegistry extends ChangeNotifier {
  final Set<Object> _tokens = {};
  bool _disposed = false;

  bool get busy => _tokens.isNotEmpty;

  void report(Object token, bool active) {
    if (_disposed) return;
    final changed = active ? _tokens.add(token) : _tokens.remove(token);
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 外壳提供的页面忙碌登记；页面内的读取不再画转圈，只登记忙碌，外壳按当前可见页面汇总。
class UiBusyScope extends InheritedWidget {
  const UiBusyScope({required this.busy, required super.child, super.key});
  final UiBusyRegistry busy;

  static UiBusyRegistry? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UiBusyScope>()?.busy;

  @override
  bool updateShouldNotify(UiBusyScope oldWidget) => busy != oldWidget.busy;
}

/// 在可见期间向 [UiBusyScope] 登记忙碌；后台页面（TickerMode 关闭）不登记。
class UiReportBusy extends StatefulWidget {
  const UiReportBusy({required this.busy, required this.child, super.key});
  final bool busy;
  final Widget child;
  @override
  State<UiReportBusy> createState() => _UiReportBusyState();
}

class _UiReportBusyState extends State<UiReportBusy> {
  final Object _token = Object();
  UiBusyRegistry? _scope;

  void _publish(bool active) {
    final scope = _scope;
    if (scope == null) return;
    // 登记会让标题栏重建，放到帧末避免在构建期间修改。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => scope.report(_token, active),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scope = UiBusyScope.maybeOf(context);
  }

  @override
  void dispose() {
    _publish(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _publish(widget.busy && TickerMode.valuesOf(context).enabled);
    return widget.child;
  }
}

/// 首次读取的内容占位。页面内只保留空白高度，进度由标题栏右上角显示；
/// 没有标题栏的面板或对话框（找不到 [UiBusyScope]）才在原位转圈。
class LoadingPlaceholder extends StatelessWidget {
  const LoadingPlaceholder({this.compact = false, super.key});
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final Widget content = UiBusyScope.maybeOf(context) == null
        ? const Center(child: LoadingGlyph(dimension: 32))
        : UiReportBusy(
            busy: true,
            child: Semantics(label: '正在加载', child: const Center()),
          );
    return compact ? SizedBox(height: 120, child: content) : content;
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
