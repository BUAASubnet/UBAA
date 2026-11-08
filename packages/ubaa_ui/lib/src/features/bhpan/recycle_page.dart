import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../shared/loading.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'chrome.dart';
import 'selection.dart';
import 'sheets.dart';
import 'write_flow.dart';
import '../../shared/dialogs/scope_boundary.dart';
import '../../shared/feedback.dart';
import '../../shared/refresh.dart';
import '../../common/state_panel.dart';

/// 回收站独立页面：恢复或永久删除；来源只提供最近 100 项。
class BhpanRecyclePage extends StatefulWidget {
  const BhpanRecyclePage({
    super.key,
    required this.service,
    required this.runWrite,
    required this.scope,
  });
  final BhpanService service;
  final BhpanWriteRunner? runWrite;
  final ValueListenable<int> scope;
  @override
  State<BhpanRecyclePage> createState() => _BhpanRecyclePageState();
}

class _BhpanRecyclePageState extends State<BhpanRecyclePage> {
  BhpanPage? _page;
  Object? _error;
  bool _loading = false, _working = false;
  int _generation = 0;
  final _selected = <String>{};
  List<(String, BhpanBatchStatus)>? _results;

  bool get _writable => widget.runWrite != null && !_working && !_loading;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  bool _current(int generation) => mounted && generation == _generation;
  Widget _boundary(Widget child) =>
      UiScopeBoundary(generation: widget.scope, child: child);

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
    });
    try {
      final page = await widget.service.read(
        const BhpanRead(BhpanReadView.recycle),
      );
      if (_current(generation)) setState(() => _page = page);
    } on Object catch (e) {
      if (_current(generation)) setState(() => _error = e);
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  Future<WriteOutcome?> _run(
    BhpanAction action,
    BhpanItem item, [
    BhpanWriteStyle style = const BhpanWriteStyle(),
  ]) async {
    final run = widget.runWrite;
    if (run == null) return null;
    final generation = _generation;
    setState(() => _working = true);
    try {
      final result = await run(
        BhpanMutation(
          action == BhpanAction.restore
              ? BhpanMutationKind.restore
              : BhpanMutationKind.deleteForever,
          target: item.handle,
        ),
        style,
      );
      if (!_current(generation) || result == null) return result;
      bhpanShowOutcome(
        context,
        action == BhpanAction.restore
            ? BhpanMutationKind.restore
            : BhpanMutationKind.deleteForever,
        result,
      );
      return result;
    } on Object catch (e) {
      if (_current(generation))
        UbaaFeedback.show(
          context,
          e is UiError ? e.message : '操作失败，请检查网络后重试',
          kind: UbaaFeedbackKind.error,
        );
      return null;
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _single(BhpanAction action, BhpanItem item) async {
    if (action == BhpanAction.details) {
      await showBhpanDetails(
        context,
        item: item,
        location: '回收站',
        boundary: _boundary,
      );
      return;
    }
    final result = await _run(action, item);
    if (mounted && result != null) await _reload();
  }

  Future<void> _reload() async {
    final generation = _generation;
    try {
      final page = await widget.service.read(
        const BhpanRead(BhpanReadView.recycle),
      );
      if (_current(generation)) setState(() => _page = page);
    } on Object catch (_) {
      // 回读失败时保留当前列表，用户可下拉重试。
    }
  }

  Future<void> _batch(BhpanAction action) async {
    final items =
        _page?.items.where((i) => _selected.contains(i.handle)).toList() ??
        const <BhpanItem>[];
    if (items.isEmpty ||
        !await bhpanConfirmBatch(
          context,
          kind: action == BhpanAction.restore
              ? BhpanMutationKind.restore
              : BhpanMutationKind.deleteForever,
          items: items,
          boundary: _boundary,
        ) ||
        !mounted)
      return;
    setState(() => _results = null);
    final results = await bhpanRunBatch(
      items,
      (item) => _run(action, item, const BhpanWriteStyle(confirmed: true)),
      isCurrent: () => mounted,
    );
    if (!mounted || results == null) return;
    setState(() {
      _results = results;
      _selected.clear();
    });
    await _reload();
  }

  Future<void> _more(BhpanItem item) async {
    final action = await bhpanActionSheet(
      context,
      item: item,
      actions: const [
        BhpanAction.restore,
        BhpanAction.details,
        BhpanAction.deleteForever,
      ],
      enabled: (a) => a == BhpanAction.details || _writable,
      location: '回收站',
      boundary: _boundary,
    );
    if (action != null && mounted) await _single(action, item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final items = _page?.items ?? const <BhpanItem>[];
    final selecting = _selected.isNotEmpty;
    Widget content;
    if (_error case final error?) {
      content = PullToRefresh(
        onRefresh: _load,
        child: RefreshViewport(
          child: UiStatePanel(
            icon: Icons.cloud_off_outlined,
            title: '没能读取回收站',
            detail: error is UiError ? error.message : '请检查网络后重试',
            action: '重试',
            onAction: _loading ? null : _load,
          ),
        ),
      );
    } else if (_page == null) {
      content = const LoadingPlaceholder();
    } else if (items.isEmpty) {
      content = PullToRefresh(
        onRefresh: _load,
        child: const RefreshViewport(
          child: UiStatePanel(icon: Icons.delete_outline, title: '回收站是空的'),
        ),
      );
    } else {
      content = PullToRefresh(
        onRefresh: _reload,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: items.length + 1,
          itemBuilder: (context, index) {
            if (index == items.length)
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _page!.range == BhpanListRange.firstHundred
                      ? '仅显示最近 100 项'
                      : '共 ${items.length} 项',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.outline,
                  ),
                ),
              );
            final item = items[index];
            void toggle() => setState(() {
              if (!_selected.remove(item.handle)) _selected.add(item.handle);
            });
            return BhpanItemTile(
              item: item,
              meta: bhpanItemMeta(item, datePrefix: '修改于 '),
              selecting: selecting,
              selected: _selected.contains(item.handle),
              enabled: !_working,
              onTap: selecting ? toggle : () => _more(item),
              onLongPress: toggle,
              onMore: () => _more(item),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('回收站')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '永久删除的文件无法找回，请先确认不再需要。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          if (_results case final results?)
            BhpanBatchResults(
              results: results,
              onClose: () => setState(() => _results = null),
            ),
          Expanded(child: content),
          if (selecting)
            BhpanSelectionBar(
              count: _selected.length,
              allSelected: _selected.length == items.length,
              actions: const [BhpanAction.restore, BhpanAction.deleteForever],
              enabled: (_) => _writable,
              onClear: () => setState(_selected.clear),
              onToggleAll: () => setState(() {
                if (_selected.length == items.length) {
                  _selected.clear();
                } else {
                  _selected.addAll(items.map((i) => i.handle));
                }
              }),
              onAction: _batch,
            ),
        ],
      ),
    );
  }
}
