import 'dart:async';
import '../../shared/loading.dart' show LoadingGlyph;
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

/// 旧版查看密码页；敏感材料不加入导航快照或通用字段。
class UbaaCgyyLockDisplayView extends StatefulWidget {
  const UbaaCgyyLockDisplayView({
    required this.open,
    this.visible = true,
    this.refreshRevision = 0,
    super.key,
  });
  final Future<CgyyLockDisplaySession> Function()? open;
  final bool visible;
  final int refreshRevision;
  @override
  State<UbaaCgyyLockDisplayView> createState() => _CgyyLockDisplayState();
}

class _CgyyLockDisplayState extends State<UbaaCgyyLockDisplayView>
    with WidgetsBindingObserver {
  CgyyLockDisplaySession? _session;
  CgyyLockDisplay? _value;
  StreamSubscription<void>? _subscription;
  Timer? _timer;
  int _generation = 0;
  bool _busy = false, _foreground = true;
  String? _error;
  bool get _visible => mounted && widget.visible && _foreground;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void didUpdateWidget(covariant UbaaCgyyLockDisplayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) {
      _close();
      return;
    }
    if (!oldWidget.visible ||
        oldWidget.refreshRevision != widget.refreshRevision)
      unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _close();
      if (mounted) setState(() {});
    } else if (widget.visible)
      unawaited(_refresh());
  }

  void _clearValue() {
    _value?.release();
    _value = null;
    _timer?.cancel();
    _timer = null;
  }

  void _close() {
    _generation++;
    _clearValue();
    unawaited(_subscription?.cancel());
    _subscription = null;
    final session = _session;
    _session = null;
    session?.cancel();
    _busy = false;
  }

  Future<void> _refresh() async {
    if (!_visible || _busy) return;
    final open = widget.open;
    if (open == null) {
      setState(() => _error = '当前无法读取门锁密码，请完成登录后重试。');
      return;
    }
    final generation = _generation;
    bool current() => _visible && generation == _generation;
    _clearValue();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_session == null) {
        final session = await open();
        if (!current()) {
          session.cancel();
          return;
        }
        _session = session;
        _subscription = session.cancelled.listen((_) {
          if (!current()) return;
          _close();
          if (mounted) setState(() => _error = '会话已变化，请重新获取密码。');
        });
      }
      final value = await _session!.read();
      if (!current()) {
        value.release();
        return;
      }
      _value = value;
    } on Object {
      if (current()) _error = '未能获取门锁信息，请重试。';
    } finally {
      if (current()) {
        setState(() => _busy = false);
        _timer = Timer(
          const Duration(seconds: 30),
          () => unawaited(_refresh()),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible || !_foreground) return const SizedBox.shrink();
    final value = _value;
    final theme = Theme.of(context);
    final code = value?.code;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: Text('密码状态', style: theme.textTheme.titleLarge)),
              IconButton(
                tooltip: '刷新密码',
                onPressed: _busy ? null : _refresh,
                icon: _busy ? const LoadingGlyph() : const Icon(Icons.refresh),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_error!, semanticsLabel: _error),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    code != null
                        ? '门锁密码'
                        : value?.hasReservation == true
                        ? '未到开门时段'
                        : _busy
                        ? '正在获取密码，请稍候…'
                        : '当前无可用预约',
                  ),
                  if (code != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      code,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (value?.dueDate case final due?) Text('有效期至 $due'),
                  ] else if (!_busy)
                    Text(
                      value?.hasReservation == true
                          ? '门锁密码会在可开门时段内返回。'
                          : '当前没有可用于获取门锁密码的预约记录。',
                    ),
                ],
              ),
            ),
          ),
          if (value != null) ...[
            const SizedBox(height: 12),
            Text('预约信息', style: theme.textTheme.titleMedium),
            for (final entry in <(String, String?)>[
              ('预约单号', value.reservationReference),
              ('场地', value.venueText),
              ('教室', value.spaceName),
              ('预约人', value.orderName),
              ('预约日期', value.reservationDate),
              ('时段', value.timeRangeText),
              ('开始时间', value.reservationStartDate),
              ('结束时间', value.reservationEndDate),
            ])
              if (entry.$2 != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.$1, style: theme.textTheme.labelMedium),
                      Text(entry.$2!),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
