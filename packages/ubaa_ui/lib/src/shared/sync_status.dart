import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 触屏平台用下拉刷新；鸿蒙版 Flutter 的平台枚举值为 `ohos`，官方 SDK 没有该常量，按名称识别。
bool uiIsTouchPlatform(BuildContext context) =>
    uiIsTouchPlatformName(Theme.of(context).platform.name) ||
    defaultTargetPlatform.name == 'ohos';

/// 按平台名称兼容官方 SDK 与 OHOS fork 的枚举。
bool uiIsTouchPlatformName(String platform) =>
    platform == 'iOS' || platform == 'android' || platform == 'ohos';

/// 标题栏右侧的统一刷新状态：刷新时转圈并显示“更新中”，空闲时显示“更新于”时间。
///
/// 页面内容区不再显示刷新转圈。短暂的刷新（如会话恢复）在 [_showDelay] 内结束时不显示，
/// 避免图标闪烁。桌面端另有刷新按钮，触屏端用下拉刷新。
class UiSyncStatus extends StatefulWidget {
  const UiSyncStatus({
    super.key,
    required this.busy,
    this.updatedAt,
    this.onRefresh,
    this.refreshTooltip = '刷新',
  });

  final bool busy;
  final DateTime? updatedAt;

  /// 为空时不显示刷新按钮（触屏端或当前页面不可刷新）。
  final Future<void> Function()? onRefresh;
  final String refreshTooltip;

  @override
  State<UiSyncStatus> createState() => _UiSyncStatusState();
}

class _UiSyncStatusState extends State<UiSyncStatus> {
  static const _showDelay = Duration(milliseconds: 400);

  Timer? _timer;
  bool _showBusy = false;
  bool _manual = false;

  bool get _busy => widget.busy || _manual;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant UiSyncStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (!_busy) {
      _timer?.cancel();
      _timer = null;
      _showBusy = false;
      return;
    }
    if (_showBusy || _timer != null) return;
    _timer = Timer(_showDelay, () {
      _timer = null;
      if (mounted && _busy) setState(() => _showBusy = true);
    });
  }

  Future<void> _refresh() async {
    final refresh = widget.onRefresh;
    // 只拦截本按钮发起的刷新；页面自身刷新时重复请求由调用方合并。
    if (refresh == null || _manual) return;
    setState(() {
      _manual = true;
      // 用户主动点按时立即反馈，不等待延迟。
      _timer?.cancel();
      _timer = null;
      _showBusy = true;
    });
    try {
      await refresh();
    } finally {
      if (mounted) {
        setState(() {
          _manual = false;
          _sync();
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _format(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final clock = '${two(local.hour)}:${two(local.minute)}';
    final sameDay =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay ? clock : '${local.month}月${local.day}日 $clock';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelMedium?.copyWith(color: color);
    final updatedAt = widget.updatedAt;
    final Widget label;
    // 登录或筛选面板覆盖当前路由时暂停不可见的忙碌动画。
    if (_showBusy && (ModalRoute.of(context)?.isCurrent ?? true)) {
      label = Row(
        key: const ValueKey('sync-busy'),
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 6),
          Text('更新中', style: style),
        ],
      );
    } else if (updatedAt != null) {
      label = Text(
        '更新于 ${_format(updatedAt)}',
        key: ValueKey(updatedAt),
        style: style,
      );
    } else {
      label = const SizedBox.shrink(key: ValueKey('sync-none'));
    }
    final status = Semantics(liveRegion: true, child: label);
    if (widget.onRefresh == null) {
      return Padding(padding: const EdgeInsets.only(right: 12), child: status);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        status,
        IconButton(
          key: const ValueKey('sync-refresh'),
          tooltip: widget.refreshTooltip,
          onPressed: _manual ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}
