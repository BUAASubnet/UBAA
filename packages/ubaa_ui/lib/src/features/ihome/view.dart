import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/dialogs/confirmation.dart' show uiConfirmIrreversible;
import '../../shared/loading.dart';
import '../../shared/refresh.dart';
import '../../common/search_field.dart';
import '../../common/chip_strip.dart';
import '../../theme.dart';
import '../../common/state_panel.dart';
part 'detail.dart';
part 'filters.dart';
part 'actions.dart';

/// 校园服务独立页面，按用户选择读取，不参与首页后台刷新。
class IhomeView extends StatefulWidget {
  const IhomeView({
    required this.service,
    this.scopeKey,
    this.connecting = false,
    super.key,
  });
  final IhomeService? service;
  final Object? scopeKey;
  final bool connecting;
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
    if (!widget.connecting) {
      unawaited(_load());
      unawaited(_loadConfig());
    }
  }

  @override
  void didUpdateWidget(covariant IhomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service) ||
        oldWidget.scopeKey != widget.scopeKey ||
        (oldWidget.connecting && !widget.connecting)) {
      final sameAccount =
          widget.scopeKey != null && oldWidget.scopeKey == widget.scopeKey;
      _revision++;
      _epoch++;
      _pendingRead = null;
      if (!sameAccount) {
        _details.clear();
        _expanded.clear();
      }
      _detailLoading.clear();
      _detailErrors.clear();
      _busy.clear();
      _submitting.clear();
      _uncertain.clear();
      if (!sameAccount) {
        _entries = [];
        _announcements = [];
        _config = null;
      }
      if (!widget.connecting) {
        unawaited(_load());
        unawaited(_loadConfig());
      }
    }
  }

  @override
  void dispose() {
    _revision++;
    _search.dispose();
    super.dispose();
  }

  void _selectScope(IhomeScope scope) {
    setState(() {
      _scope = scope;
      _notices = false;
      _filter = scope == IhomeScope.mine ? IhomeFilter.newest : IhomeFilter.all;
      _keyword = '';
      _search.clear();
      _category = null;
    });
    unawaited(_load(reset: true));
  }

  void _setFilter(IhomeFilter value) => setState(() => _filter = value);
  void _setCategory(int? value) =>
      setState(() => _category = value == 0 ? null : value);
  String _entryKey(IhomeEntry e) => e.evaluation == null
      ? 'appeal:${e.appeal.id}'
      : 'evaluation:${e.evaluation!.id}';
  Future<void> _loadConfig() async {
    final service = widget.service;
    if (service == null || widget.connecting) return;
    try {
      final result = await service.config();
      if (mounted && identical(service, widget.service))
        setState(() {
          _config = result.data;
          _configError = null;
        });
    } on Object {
      if (mounted && identical(service, widget.service))
        setState(() => _configError = '分类与设置读取失败');
    }
  }

  Future<void>? _pendingRead;
  Future<void> _load({bool more = false, bool reset = false}) {
    if (!reset && _pendingRead != null) return _pendingRead!;
    late final Future<void> read;
    read = _fetch(more: more, reset: reset).whenComplete(() {
      if (identical(_pendingRead, read)) _pendingRead = null;
    });
    _pendingRead = read;
    return read;
  }

  Future<void> _fetch({bool more = false, bool reset = false}) async {
    final service = widget.service;
    if (service == null) return;
    if (widget.connecting) {
      if (reset)
        setState(() {
          _entries = [];
          _announcements = [];
          _page = 1;
          _hasMore = false;
          _expanded.clear();
          _details.clear();
        });
      return;
    }
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
        IhomeQuery query(int page) => IhomeQuery(
          scope: _scope,
          page: page,
          limit: 15,
          keyword: _keyword,
          filter: _filter,
          categoryId: _category,
        );
        final lastVisiblePage = more || reset ? requested : _page;
        var result = await service.page(query(requested));
        if (!mounted || revision != _revision) return;
        final received = [...result.data.entries];
        // 刷新已经展开的分页范围，整批到达后替换，保留当前滚动位置。
        while (!more &&
            result.data.page < lastVisiblePage &&
            result.data.page < result.data.lastPage) {
          final nextPage = result.data.page + 1;
          result = await service.page(query(nextPage));
          if (!mounted || revision != _revision) return;
          if (result.data.page != nextPage) throw StateError('分页读取未前进');
          received.addAll(result.data.entries);
        }
        final oldIds = more ? _entries.map(_entryKey).toSet() : <String>{};
        final unique = <IhomeEntry>[];
        for (final entry in received) {
          if (oldIds.add(_entryKey(entry))) unique.add(entry);
        }
        final stagnant =
            more && (result.data.page < requested || unique.isEmpty);
        setState(() {
          if (!stagnant) {
            if (!more) {
              final ids = unique.map((entry) => entry.appeal.id).toSet();
              _details.removeWhere((id, _) => !ids.contains(id));
            }
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
              (!more || !_details.containsKey(entry.appeal.id))) {
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
      return const UiStatePanel(
        icon: Icons.block_outlined,
        title: '此版本暂不支持 iHome',
      );
    final empty = _notices ? _announcements.isEmpty : _entries.isEmpty;
    final headers = <Widget>[
      Row(
        children: [
          Expanded(
            child: UiChipStrip(
              spacing: 8,
              bleed: true,
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
                        : (_) => _selectScope(item.$1),
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
              ],
            ),
          ),
          if (Theme.of(context).platform
              case TargetPlatform.macOS ||
                  TargetPlatform.windows ||
                  TargetPlatform.linux ||
                  TargetPlatform.fuchsia)
            IconButton(
              tooltip: '刷新',
              onPressed: _loading || _busy.isNotEmpty ? null : () => _load(),
              icon: _loading && !empty
                  ? const LoadingGlyph()
                  : const Icon(Icons.refresh),
            ),
        ],
      ),
      if (!_notices) ..._filters() else const SizedBox(height: 12),
      // 只有首次读取在页面内占位；刷新保留原内容。
      if (_loading && empty) const LoadingPlaceholder(compact: true),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: UiInlineRetry(message: _error!, onRetry: () => _load()),
        ),
      if (_configError != null && !_notices)
        UiInlineRetry(message: _configError!, onRetry: _loadConfig),
      if (!_loading && _error == null && empty)
        const UiStatePanel(
          compact: true,
          icon: Icons.inbox_outlined,
          title: '暂无内容',
        ),
    ];
    final count = _notices ? _announcements.length : _entries.length;
    final indices = <Key, int>{
      for (var i = 0; i < count; i++)
        ValueKey(
          _notices ? '$_epoch:${_announcements[i].id}' : _entryKey(_entries[i]),
        ): headers.length + i,
    };
    return PullToRefresh(
      onRefresh: () => _load(),
      child: ListView.builder(
        padding: UbaaTheme.pageInsets(context, top: 8),
        itemCount: headers.length + count + (_hasMore ? 1 : 0),
        findChildIndexCallback: (key) => indices[key],
        itemBuilder: (context, index) {
          if (index < headers.length) return headers[index];
          final item = index - headers.length;
          if (item == count)
            return Center(
              child: OutlinedButton.icon(
                onPressed: _loading ? null : () => _load(more: true),
                icon: _loading
                    ? const LoadingGlyph()
                    : const Icon(Icons.expand_more),
                label: const Text('加载更多'),
              ),
            );
          if (_notices) {
            final notice = _announcements[item];
            return _IhomeNoticeCard(
              key: ValueKey('$_epoch:${notice.id}'),
              service: widget.service!,
              notice: notice,
            );
          }
          return _appealCard(context, _entries[item]);
        },
      ),
    );
  }
}
