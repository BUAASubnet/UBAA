import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../theme.dart';
part 'detail.dart';
part 'filters.dart';
part 'actions.dart';

/// 校园服务独立页面，按用户选择读取，不参与首页后台刷新。
class IhomeView extends StatefulWidget {
  const IhomeView({required this.service, super.key});
  final IhomeService? service;
  @override
  State<IhomeView> createState() => _IhomeViewState();
}

class _IhomeViewState extends State<IhomeView> {
  final _search = TextEditingController();
  IhomeScope _scope = IhomeScope.public;
  IhomeFilter _filter = IhomeFilter.all;
  int? _category;
  bool _notices = false, _loading = false, _hasMore = false;
  int _revision = 0, _page = 1;
  String _keyword = '';
  List<IhomeEntry> _entries = [];
  List<IhomeNotice> _announcements = [];
  IhomeConfig? _config;
  String? _error, _configError;
  ConnectionMode? _route;
  int _epoch = 0;
  final _details = <int, IhomeResult<IhomeAppeal>>{};
  final _expanded = <String>{};
  final _detailLoading = <int>{};
  final _detailErrors = <int, String>{};
  final _busy = <int>{};
  final _submitting = <int>{};
  final _uncertain = <int>{};
  void _update(VoidCallback action) => setState(action);
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadConfig());
  }

  @override
  void didUpdateWidget(covariant IhomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      _revision++;
      _epoch++;
      _details.clear();
      _expanded.clear();
      _detailLoading.clear();
      _detailErrors.clear();
      _busy.clear();
      _submitting.clear();
      _uncertain.clear();
      _entries = [];
      _announcements = [];
      _config = null;
      unawaited(_load());
      unawaited(_loadConfig());
    }
  }

  @override
  void dispose() {
    _revision++;
    _search.dispose();
    super.dispose();
  }

  void _setFilter(IhomeFilter value) => setState(() => _filter = value);
  void _setCategory(int? value) =>
      setState(() => _category = value == 0 ? null : value);
  String _entryKey(IhomeEntry e) => e.evaluation == null
      ? 'appeal:${e.appeal.id}'
      : 'evaluation:${e.evaluation!.id}';
  Future<void> _loadConfig() async {
    final service = widget.service;
    if (service == null) return;
    try {
      final result = await service.config();
      if (mounted && identical(service, widget.service))
        setState(() {
          _config = result.data;
          _configError = null;
        });
    } on Object {
      if (mounted && identical(service, widget.service))
        setState(() => _configError = '分类和支持设置读取失败');
    }
  }

  Future<void> _load({bool more = false, bool reset = false}) async {
    final service = widget.service;
    if (service == null) return;
    if (_busy.isNotEmpty) return;
    final revision = ++_revision;
    final requested = more ? _page + 1 : 1;
    setState(() {
      _loading = true;
      _error = null;
      _detailLoading.clear();
      if (reset) {
        _entries = [];
        _announcements = [];
        _hasMore = false;
        _route = null;
        _expanded.clear();
        _details.clear();
      }
    });
    try {
      if (_notices) {
        final result = await service.notices();
        if (!mounted || revision != _revision) return;
        setState(() {
          _announcements = result.data;
          _route = result.route;
        });
      } else {
        final result = await service.page(
          IhomeQuery(
            scope: _scope,
            page: requested,
            limit: 15,
            keyword: _keyword,
            filter: _filter,
            categoryId: _category,
          ),
        );
        if (!mounted || revision != _revision) return;
        final oldIds = more ? _entries.map(_entryKey).toSet() : <String>{};
        final unique = <IhomeEntry>[];
        for (final entry in result.data.entries) {
          if (oldIds.add(_entryKey(entry))) unique.add(entry);
        }
        final stagnant =
            more && (result.data.page < requested || unique.isEmpty);
        setState(() {
          if (!stagnant) {
            if (!more) _details.clear();
            _entries = more ? [..._entries, ...unique] : unique;
            _page = result.data.page;
          }
          _hasMore =
              !stagnant &&
              unique.isNotEmpty &&
              result.data.page < result.data.lastPage;
          _route = result.route;
        });
        for (final entry in _entries) {
          if (_expanded.contains(_entryKey(entry)) &&
              !_details.containsKey(entry.appeal.id)) {
            unawaited(_readDetail(entry.appeal.id));
          }
        }
      }
    } on Object catch (error) {
      if (mounted && revision == _revision)
        setState(
          () => _error = error is UiError ? error.message : '读取失败，请稍后重试',
        );
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.service == null)
      return const Center(child: Text('当前客户端暂不支持 iHome'));
    return RefreshIndicator(
      onRefresh: () => _load(),
      child: ListView(
        padding: EdgeInsets.all(
          UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width),
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in const [
                (IhomeScope.public, '诉求广场'),
                (IhomeScope.mine, '我的诉求'),
                (IhomeScope.followed, '我的关注'),
                (IhomeScope.appraised, '我的评价'),
              ])
                ChoiceChip(
                  label: Text(item.$2),
                  selected: !_notices && _scope == item.$1,
                  onSelected: _busy.isNotEmpty
                      ? null
                      : (_) {
                          setState(() {
                            _scope = item.$1;
                            _notices = false;
                            _filter = item.$1 == IhomeScope.mine
                                ? IhomeFilter.newest
                                : IhomeFilter.all;
                            _keyword = '';
                            _search.clear();
                            _category = null;
                          });
                          unawaited(_load(reset: true));
                        },
                ),
              ChoiceChip(
                label: const Text('公告'),
                selected: _notices,
                onSelected: _busy.isNotEmpty
                    ? null
                    : (_) {
                        setState(() => _notices = true);
                        unawaited(_load(reset: true));
                      },
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading || _busy.isNotEmpty ? null : () => _load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (!_notices) ..._filters(),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Text(_error!),
                  TextButton(onPressed: () => _load(), child: const Text('重试')),
                ],
              ),
            ),
          if (_configError != null && !_notices)
            Row(
              children: [
                Expanded(child: Text(_configError!)),
                TextButton(onPressed: _loadConfig, child: const Text('重试')),
              ],
            ),
          if (!_loading &&
              _error == null &&
              (_notices ? _announcements.isEmpty : _entries.isEmpty))
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('暂无内容')),
            ),
          if (_notices)
            for (final notice in _announcements)
              _IhomeNoticeCard(
                key: ValueKey('${_epoch}:${notice.id}'),
                service: widget.service!,
                notice: notice,
              ),
          if (!_notices)
            for (final entry in _entries) _appealCard(context, entry),
          if (_hasMore)
            TextButton(
              onPressed: _loading ? null : () => _load(more: true),
              child: const Text('加载更多'),
            ),
        ],
      ),
    );
  }
}
