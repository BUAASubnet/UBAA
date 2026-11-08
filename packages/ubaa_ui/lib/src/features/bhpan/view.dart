import '../../theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'chrome.dart';
import 'dialogs.dart';
import 'format.dart';
import 'location.dart';
import 'recycle_page.dart';
import 'selection.dart';
import 'share_form.dart';
import 'shares_page.dart';
import 'sheets.dart';
import 'transfer_view.dart';
import 'write_flow.dart';
import 'create_menu.dart';
import '../../shared/dialogs/scope_boundary.dart';
import '../../shared/dialogs/form_page.dart' show showUiPage;
import '../../shared/feedback.dart';
import '../../shared/refresh.dart';
import '../../shared/sync_status.dart';
import '../../common/state_panel.dart';

part 'view_transfer.dart';
part 'view_content.dart';

class BhpanAccess {
  const BhpanAccess({
    this.service,
    this.runWrite,
    this.pickFile,
    this.pickDownload,
    this.previewFile,
  });
  final BhpanService? service;
  final BhpanWriteRunner? runWrite;
  final Future<BhpanLocalFile?> Function()? pickFile;
  final Future<BhpanDownloadDestination?> Function(
    String name,
    bool Function() isCurrent,
  )?
  pickDownload;

  /// 系统预览：宿主提供应用私有临时位置，`deliver` 调起系统预览，`discard` 清理临时文件。
  final Future<BhpanDownloadDestination?> Function(
    String name,
    bool Function() isCurrent,
  )?
  previewFile;
}

/// 外壳的返回按钮和系统返回先交给云盘处理：逐级回到上一层，到顶后才退出。
class BhpanBackHandle {
  bool Function()? _handler;

  /// 云盘消费了这次返回时为 true。
  bool handleBack() => _handler?.call() ?? false;
}

enum BhpanSortKey { name, modified, size }

/// 校园与空间指标共用的云盘页面。
class BhpanView extends StatefulWidget {
  const BhpanView({required this.access, this.backHandle, super.key});
  final BhpanAccess access;
  final BhpanBackHandle? backHandle;
  @override
  State<BhpanView> createState() => _BhpanViewState();
}

class _BhpanViewState extends State<BhpanView> {
  /// 当前位置的根：个人文档库、某类文档库列表或收到的分享。
  BhpanRead _base = const BhpanRead(BhpanReadView.personalRoot);
  BhpanRead _query = const BhpanRead(BhpanReadView.personalRoot);
  BhpanRootKind _rootKind = BhpanRootKind.personal;
  final _trail = <BhpanItem>[];

  /// 个人文档库自动进入唯一根目录，该层不显示在路径里，也不能再向上返回。
  int _baseDepth = 0;
  BhpanPage? _page;
  Object? _error;
  String _filter = '';
  final _search = TextEditingController();
  final _keys = FocusNode(debugLabel: 'bhpan-keys');
  final _searchFocus = FocusNode(debugLabel: 'bhpan-search');
  bool _searchVisible = false;
  bool _loading = false, _working = false;
  BhpanSortKey _sort = BhpanSortKey.name;
  bool _ascending = true;
  int _generation = 0;
  final _scope = ValueNotifier<int>(0);
  Object? _mutationActivity;
  final _selected = <String>{};
  List<(String, BhpanBatchStatus)>? _batchResults;
  BhpanTransferTask? _transfer;
  BhpanTransferProgress? _progress;
  String? _progressLabel;
  bool _progressUpload = true;
  Timer? _progressTimer, _progressHide;
  BhpanService? get _service => widget.access.service;
  bool get _writable =>
      widget.access.runWrite != null && !_working && !_loading;
  bool get _busy => _loading || _working;
  bool get _received => _base.view == BhpanReadView.receivedShare;

  @override
  void initState() {
    super.initState();
    widget.backHandle?._handler = _handleBack;
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant BhpanView old) {
    super.didUpdateWidget(old);
    if (!identical(old.backHandle, widget.backHandle)) {
      if (identical(old.backHandle?._handler, _handleBack))
        old.backHandle?._handler = null;
      widget.backHandle?._handler = _handleBack;
    }
    if (!identical(old.access.service, _service)) {
      _scope.value++;
      _mutationActivity = null;
      _working = false;
      _transfer?.cancel();
      _progressTimer?.cancel();
      _transfer = null;
      _progress = null;
      _batchResults = null;
      _generation++;
      _page = null;
      _trail.clear();
      _selected.clear();
      _clearSearch();
      _rootKind = BhpanRootKind.personal;
      _base = _query = const BhpanRead(BhpanReadView.personalRoot);
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    if (identical(widget.backHandle?._handler, _handleBack))
      widget.backHandle?._handler = null;
    _scope.value++;
    _scope.dispose();
    _search.dispose();
    _keys.dispose();
    _searchFocus.dispose();
    _transfer?.cancel();
    _progressTimer?.cancel();
    _progressHide?.cancel();
    _generation++;
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  Widget _dialogScope(Widget child) =>
      UiScopeBoundary(generation: _scope, child: child);
  bool _current(int generation) => mounted && generation == _generation;
  String _message(Object e) => e is UiError ? e.message : '云盘操作未完成，请检查连接后重试';
  void _notify(
    String message, [
    UbaaFeedbackKind kind = UbaaFeedbackKind.info,
  ]) {
    if (mounted) UbaaFeedback.show(context, message, kind: kind);
  }

  /// 页面快捷键节点已持有焦点，SearchBar 的 autoFocus 不生效，这里显式聚焦。
  void _openSearch() {
    setState(() => _searchVisible = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _clearSearch() {
    _searchVisible = false;
    _filter = '';
    _search.clear();
    // 搜索框移除后焦点收回页面，⌘F 等快捷键继续可用。
    _keys.requestFocus();
  }

  /// [keep] 为 true 时保留当前列表（刷新、写入后回读），否则显示骨架。
  Future<void> _load({bool reconnect = false, bool keep = false}) async {
    final service = _service;
    if (service == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
      if (!keep) _page = null;
    });
    try {
      if (reconnect) {
        await service.login();
        _trail.clear();
        _query = _base;
      }
      if (!_current(generation)) return;
      var result = await service.read(_query);
      if (!_current(generation)) return;
      if (_query.view == BhpanReadView.personalRoot) {
        _baseDepth = 0;
        if (result.items.length == 1) {
          final root = result.items.single;
          _trail
            ..clear()
            ..add(root);
          _baseDepth = 1;
          _query = BhpanRead(BhpanReadView.directory, target: root.handle);
          result = await service.read(_query);
        }
      }
      if (_current(generation)) setState(() => _page = result);
    } on Object catch (e) {
      if (_current(generation))
        setState(() {
          _error = e;
          _page = null;
        });
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() => _load(keep: true);

  Future<void> _open(BhpanItem item) async {
    if (!item.isFolder || item.scope == BhpanScope.recycle) return;
    _trail.add(item);
    _query = BhpanRead(BhpanReadView.directory, target: item.handle);
    _clearSearch();
    await _load();
  }

  Future<void> _goTo(int trailIndex) async {
    _trail.removeRange(trailIndex + 1, _trail.length);
    _query = BhpanRead(BhpanReadView.directory, target: _trail.last.handle);
    _clearSearch();
    await _load();
  }

  Future<void> _goRoot() async {
    if (_baseDepth > 0 && _trail.isNotEmpty) return _goTo(_baseDepth - 1);
    _trail.clear();
    _query = _base;
    _clearSearch();
    await _load();
  }

  bool _handleBack() {
    if (_selected.isNotEmpty) {
      setState(_selected.clear);
      return true;
    }
    if (_searchVisible) {
      setState(_clearSearch);
      return true;
    }
    if (_trail.length <= _baseDepth) return false;
    unawaited(_trail.length >= 2 ? _goTo(_trail.length - 2) : _goRoot());
    return true;
  }

  Future<void> _switchLibrary(BhpanRootKind kind) async {
    _rootKind = kind;
    _trail.clear();
    _baseDepth = 0;
    _base = _query = kind == BhpanRootKind.personal
        ? const BhpanRead(BhpanReadView.personalRoot)
        : BhpanRead(BhpanReadView.roots, root: kind);
    _clearSearch();
    await _load();
  }

  Future<void> _places() async {
    final choice = await showBhpanPlaces(
      context,
      current: _received ? null : _rootKind,
      boundary: _dialogScope,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case BhpanLibraryChoice(:final kind):
        await _switchLibrary(kind);
      case BhpanToolChoice(tool: BhpanTool.shares):
        await _openShares();
      case BhpanToolChoice(tool: BhpanTool.recycle):
        await _openRecycle();
      case BhpanToolChoice(tool: BhpanTool.openLink):
        await _receivedShare();
    }
  }

  Future<void> _push(Widget page) async {
    final generation = _generation;
    // 回收站、分享管理：宽窗口为大对话框，不盖住侧边栏。
    await showUiPage<void>(
      context,
      dialogWidth: 720,
      fixedHeight: true,
      builder: (_) => _dialogScope(page),
    );
    if (_current(generation)) await _refresh();
  }

  Future<void> _openShares({BhpanItem? item}) async {
    final service = _service;
    if (service == null) return;
    await _push(
      BhpanSharesPage(
        service: service,
        runWrite: widget.access.runWrite,
        scope: _scope,
        item: item,
      ),
    );
  }

  Future<void> _openRecycle() async {
    final service = _service;
    if (service == null) return;
    await _push(
      BhpanRecyclePage(
        service: service,
        runWrite: widget.access.runWrite,
        scope: _scope,
      ),
    );
  }

  Future<WriteOutcome?> _mutate(
    BhpanMutation request, [
    BhpanWriteStyle style = const BhpanWriteStyle(),
    bool rethrowErrors = false,
  ]) async {
    final run = widget.access.runWrite;
    if (run == null || _working) return null;
    final generation = _generation;
    final activity = Object();
    _mutationActivity = activity;
    setState(() => _working = true);
    try {
      final result = await run(request, style);
      if (!_current(generation) || result == null) return null;
      UbaaFeedback.showOutcome(context, result);
      final share = result.result?.bhpanReceipt?.share;
      if (share != null) {
        await bhpanShowShareLink(
          context,
          service: _service!,
          share: share,
          boundary: _dialogScope,
          isCurrent: () => _current(generation),
        );
      } else if (result.error == null ||
          result.error?.code == UbaaErrorCode.outcomeUnknown) {
        _mutationActivity = null;
        _working = false;
        await _load(keep: true);
      }
      return result;
    } on Object catch (e) {
      if (rethrowErrors) rethrow;
      if (_current(generation)) _notify(_message(e), UbaaFeedbackKind.error);
      return null;
    } finally {
      if (mounted && identical(_mutationActivity, activity))
        setState(() {
          _mutationActivity = null;
          _working = false;
        });
    }
  }

  String get _rootLabel => _received ? '收到的分享' : bhpanLibraryNames[_rootKind]!;

  /// 详细信息里的位置：根名称加上已进入的目录。
  String get _locationText =>
      [_rootLabel, for (final f in _trail.skip(_baseDepth)) f.name].join(' / ');

  List<BhpanAction> _actionsFor(BhpanItem item) =>
      item.scope == BhpanScope.receivedShare
      ? const [
          BhpanAction.download,
          BhpanAction.saveToMine,
          BhpanAction.details,
        ]
      : const [
          BhpanAction.download,
          BhpanAction.share,
          BhpanAction.move,
          BhpanAction.rename,
          BhpanAction.copy,
          BhpanAction.details,
          BhpanAction.shareRecords,
          BhpanAction.recycle,
        ];

  bool _actionEnabled(BhpanAction a) => switch (a) {
    BhpanAction.details || BhpanAction.shareRecords => !_busy,
    BhpanAction.download => !_busy && widget.access.pickDownload != null,
    BhpanAction.view => !_busy && widget.access.previewFile != null,
    _ => _writable,
  };

  Future<WriteOutcome?> _action(
    BhpanAction action,
    BhpanItem item, {
    BhpanWriteStyle style = const BhpanWriteStyle(),
  }) async {
    final service = _service;
    if (service == null) return null;
    final generation = _generation;
    try {
      switch (action) {
        case BhpanAction.details:
          await _showDetails(item);
          return null;
        case BhpanAction.shareRecords:
          await _openShares(item: item);
          return null;
        case BhpanAction.download:
          await _download([item]);
          return null;
        case BhpanAction.rename:
          final name = await bhpanText(
            context,
            scope: _scope,
            title: '重命名',
            label: '新名称',
            initial: item.name,
            action: '重命名',
          );
          if (!_current(generation) || name == null || name == item.name)
            return null;
          return _mutate(
            BhpanMutation(
              BhpanMutationKind.rename,
              target: item.handle,
              name: name,
            ),
            const BhpanWriteStyle(confirmed: true),
          );
        case BhpanAction.move || BhpanAction.copy || BhpanAction.saveToMine:
          final verb = action == BhpanAction.move
              ? '移动'
              : action == BhpanAction.copy
              ? '复制'
              : '保存';
          final dest = await bhpanDestination(
            context,
            service,
            scope: _scope,
            title: '$verb「${item.name}」到…',
            action: '$verb到此处',
            exclude: {item.handle},
            start: action == BhpanAction.saveToMine ? null : _personalStart,
            disabledTarget: action == BhpanAction.move
                ? _trail.lastOrNull?.handle
                : null,
          );
          if (!_current(generation) || dest == null) return null;
          return _mutate(
            BhpanMutation(
              action == BhpanAction.move
                  ? BhpanMutationKind.move
                  : BhpanMutationKind.copy,
              target: item.handle,
              destination: dest.handle,
            ),
          );
        case BhpanAction.share:
          final settings = await bhpanShareDialog(
            context,
            scope: _scope,
            title: item.name,
            isFolder: item.isFolder,
          );
          if (!_current(generation) || settings == null) return null;
          return _mutate(
            BhpanMutation(
              BhpanMutationKind.createShare,
              target: item.handle,
              settings: settings,
            ),
          );
        case BhpanAction.recycle:
          return _mutate(
            BhpanMutation(BhpanMutationKind.recycle, target: item.handle),
            style,
          );
        case BhpanAction.view:
          await _download([item], preview: true);
          return null;
        case BhpanAction.restore || BhpanAction.deleteForever:
          return null;
      }
    } on Object catch (e) {
      if (_current(generation)) _notify(_message(e), UbaaFeedbackKind.error);
      return null;
    }
  }

  bool _canPreview(BhpanItem item) =>
      widget.access.previewFile != null && bhpanPreviewable(item);

  /// 点文件：可预览且不太大时直接打开，其余弹出下载面板（仍可选择查看）。
  Future<void> _tapFile(BhpanItem item) async {
    if (_canPreview(item) && (item.bytes ?? 0) <= bhpanPreviewLimit) {
      await _download([item], preview: true);
      return;
    }
    await _showDetails(item, primary: true);
  }

  Future<void> _showDetails(BhpanItem item, {bool primary = false}) async {
    final service = _service;
    if (service == null) return;
    final action = await showBhpanDetails(
      context,
      item: item,
      location: _locationText,
      folderSize: () => service.size(item.handle),
      primary: primary
          ? [BhpanAction.download, if (_canPreview(item)) BhpanAction.view]
          : const [],
      enabled: _actionEnabled,
      boundary: _dialogScope,
    );
    if (action != null && mounted) await _action(action, item);
  }

  Future<void> _receivedShare() async {
    final generation = _generation;
    final input = await bhpanOpenShareDialog(context, scope: _scope);
    if (!_current(generation) || input == null) return;
    _trail.clear();
    _baseDepth = 0;
    _clearSearch();
    _base = _query = BhpanRead(
      BhpanReadView.receivedShare,
      link: input.$1,
      password: input.$2,
    );
    final expected = _generation + 1;
    await _load();
    if (!_current(expected)) return;
    final items = _page?.items;
    if (items != null && items.length == 1 && items.first.isFolder)
      await _open(items.first);
  }

  Future<void> _newFolder() async {
    if (_trail.isEmpty) return;
    final parent = _trail.last;
    final generation = _generation;
    final name = await bhpanText(
      context,
      scope: _scope,
      title: '新建文件夹',
      label: '名称',
      action: '新建',
    );
    if (!_current(generation) || name == null) return;
    await _mutate(
      BhpanMutation(
        BhpanMutationKind.createFolder,
        target: parent.handle,
        name: name,
      ),
      const BhpanWriteStyle(confirmed: true),
    );
  }

  List<BhpanItem> get _selectedItems =>
      _page?.items.where((i) => _selected.contains(i.handle)).toList() ??
      const [];

  Future<void> _batch(BhpanAction action) async {
    final items = _selectedItems;
    if (action == BhpanAction.download) {
      await _download(items);
      return;
    }
    final service = _service;
    if (service == null || items.isEmpty) return;
    final generation = _generation;
    final kind = switch (action) {
      BhpanAction.move => BhpanMutationKind.move,
      BhpanAction.copy => BhpanMutationKind.copy,
      _ => BhpanMutationKind.recycle,
    };
    BhpanItem? destination;
    if (kind != BhpanMutationKind.recycle) {
      destination = await bhpanDestination(
        context,
        service,
        scope: _scope,
        title:
            '${action == BhpanAction.move ? '移动' : '复制'} ${items.length} 项到…',
        action: action == BhpanAction.move ? '移动到此处' : '复制到此处',
        exclude: {for (final i in items) i.handle},
        start: _personalStart,
        disabledTarget: action == BhpanAction.move
            ? _trail.lastOrNull?.handle
            : null,
      );
      if (!_current(generation) || destination == null) return;
    }
    if (!mounted ||
        !await bhpanConfirmBatch(
          context,
          kind: kind,
          items: items,
          destination: destination?.name,
          boundary: _dialogScope,
        ) ||
        !_current(generation))
      return;
    setState(() => _batchResults = null);
    final results = await bhpanRunBatch(
      items,
      (item) => _mutate(
        BhpanMutation(
          kind,
          target: item.handle,
          destination: destination?.handle,
        ),
        const BhpanWriteStyle(confirmed: true),
      ),
      isCurrent: () => mounted && identical(service, _service),
    );
    if (mounted && results != null)
      setState(() {
        _batchResults = results;
        _selected.clear();
      });
  }

  /// 目标选择从当前个人目录开始；其他文档库只能选个人文档库作为目标。
  List<BhpanItem>? get _personalStart =>
      !_received && _rootKind == BhpanRootKind.personal && _baseDepth > 0
      ? List.of(_trail)
      : null;

  bool get _canUpload =>
      !_busy &&
      widget.access.pickFile != null &&
      widget.access.runWrite != null &&
      _trail.isNotEmpty &&
      _trail.last.isFolder &&
      _trail.last.scope != BhpanScope.recycle;

  /// 收到的分享不能新建目录；其他文档库是否可写由服务端判断，失败时说明原因。
  bool get _canCreateFolder =>
      !_received &&
      widget.access.runWrite != null &&
      _trail.isNotEmpty &&
      _trail.last.scope == BhpanScope.personal &&
      _query.view == BhpanReadView.directory;

  /// 只有个人文档库先试秒传。
  bool get _tryFastUpload => !_received && _rootKind == BhpanRootKind.personal;

  int _compare(BhpanItem a, BhpanItem b) {
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    final order = switch (_sort) {
      BhpanSortKey.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      BhpanSortKey.modified => (a.modifiedAt ?? DateTime(0)).compareTo(
        b.modifiedAt ?? DateTime(0),
      ),
      BhpanSortKey.size => (a.bytes ?? 0).compareTo(b.bytes ?? 0),
    };
    return _ascending ? order : -order;
  }

  Widget _sortButton() => PopupMenuButton<Object>(
    tooltip: '排序',
    icon: const Icon(Icons.sort),
    onSelected: (value) => setState(() {
      if (value is BhpanSortKey) {
        if (value != _sort) {
          _sort = value;
          // 时间和大小默认从新到旧、从大到小。
          _ascending = value == BhpanSortKey.name;
        }
      } else if (value is bool) {
        _ascending = value;
      }
    }),
    itemBuilder: (_) => [
      for (final (key, label) in const [
        (BhpanSortKey.name, '名称'),
        (BhpanSortKey.modified, '修改时间'),
        (BhpanSortKey.size, '大小'),
      ])
        CheckedPopupMenuItem<Object>(
          value: key,
          checked: _sort == key,
          child: Text(label),
        ),
      const PopupMenuDivider(),
      CheckedPopupMenuItem<Object>(
        value: true,
        checked: _ascending,
        child: Text(switch (_sort) {
          BhpanSortKey.name => 'A → Z',
          BhpanSortKey.modified => '从旧到新',
          BhpanSortKey.size => '从小到大',
        }),
      ),
      CheckedPopupMenuItem<Object>(
        value: false,
        checked: !_ascending,
        child: Text(switch (_sort) {
          BhpanSortKey.name => 'Z → A',
          BhpanSortKey.modified => '从新到旧',
          BhpanSortKey.size => '从大到小',
        }),
      ),
    ],
  );

  Widget _locationBar() => BhpanLocationBar(
    rootLabel: _rootLabel,
    rootIcon: _received
        ? Icons.move_to_inbox_outlined
        : bhpanLibraryIcons[_rootKind]!,
    names: [for (final f in _trail.skip(_baseDepth)) f.name],
    enabled: !_busy,
    onPlaces: _places,
    onRoot: _goRoot,
    onIndex: (index) => _goTo(index + _baseDepth),
    actions: [
      IconButton(
        tooltip: '搜索',
        isSelected: _searchVisible,
        onPressed: () =>
            _searchVisible ? setState(_clearSearch) : _openSearch(),
        icon: const Icon(Icons.search),
      ),
      _sortButton(),
      if (!uiIsTouchPlatform(context))
        IconButton(
          tooltip: '刷新',
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_service == null) {
      return const UiStatePanel(
        icon: Icons.cloud_off_outlined,
        title: '此版本暂不支持北航云盘',
      );
    }
    final query = _filter.toLowerCase();
    final items =
        (_page?.items
                  .where((i) => i.name.toLowerCase().contains(query))
                  .toList() ??
              <BhpanItem>[])
          ..sort(_compare);
    final selecting = _selected.isNotEmpty;
    final all = _page?.items ?? const <BhpanItem>[];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _locationBar(),
        if (_searchVisible)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              controller: _search,
              focusNode: _searchFocus,
              hintText: '在此文件夹中搜索',
              elevation: const WidgetStatePropertyAll(0),
              leading: const Icon(Icons.search),
              trailing: [
                if (_filter.isNotEmpty)
                  IconButton(
                    tooltip: '清除',
                    onPressed: () => setState(() {
                      _search.clear();
                      _filter = '';
                    }),
                    icon: const Icon(Icons.close),
                  ),
              ],
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        if (_progress case final progress?)
          BhpanProgressTile(
            progress: progress,
            label: _progressLabel,
            upload: _progressUpload,
            onCancel: _transfer?.cancel,
            onClose: () => setState(() => _progress = null),
          ),
        if (_batchResults case final results?)
          BhpanBatchResults(
            results: results,
            onClose: () => setState(() => _batchResults = null),
          ),
        Expanded(child: _content(items, selecting)),
        if (selecting)
          BhpanSelectionBar(
            count: _selected.length,
            allSelected: _selected.length == all.length,
            actions: _received
                ? const [BhpanAction.download]
                : const [
                    BhpanAction.download,
                    BhpanAction.move,
                    BhpanAction.copy,
                    BhpanAction.recycle,
                  ],
            enabled: (a) => a == BhpanAction.download ? !_busy : _writable,
            onClear: () => setState(_selected.clear),
            onToggleAll: () => setState(() {
              if (_selected.length == all.length) {
                _selected.clear();
              } else {
                _selected.addAll(all.map((i) => i.handle));
              }
            }),
            onAction: _batch,
          ),
      ],
    );
    final showFab =
        !selecting && _page != null && (_canUpload || _canCreateFolder);
    // 桌面快捷键：⌘/Ctrl+F 打开搜索，Esc 先退出多选、再关闭搜索。
    void escape() {
      if (_selected.isNotEmpty) {
        setState(_selected.clear);
      } else if (_searchVisible) {
        setState(_clearSearch);
      }
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): escape,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
      },
      child: Focus(
        focusNode: _keys,
        autofocus: true,
        child: Stack(
          children: [
            // 云盘行内边距按手机 16 设计；宽屏补齐到页面统一左右边线。
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal:
                      UbaaTheme.pagePadding(MediaQuery.sizeOf(context).width) -
                      16,
                ),
                child: body,
              ),
            ),
            if (showFab)
              Positioned.fill(
                child: BhpanCreateMenu(
                  enabled: !_busy,
                  onUpload: _canUpload ? _upload : null,
                  onNewFolder: _canCreateFolder ? _newFolder : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer(int count) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Text(
      _filter.isNotEmpty ? '找到 $count 项' : '共 $count 项',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.outline,
      ),
    ),
  );

  Widget _row(BhpanItem item, bool selecting) {
    void toggle() => setState(() {
      if (!_selected.remove(item.handle)) _selected.add(item.handle);
    });
    return BhpanItemTile(
      item: item,
      selecting: selecting,
      selected: _selected.contains(item.handle),
      enabled: !_busy,
      onTap: selecting
          ? toggle
          : () => item.isFolder ? _open(item) : _tapFile(item),
      onLongPress: toggle,
      onMore: () async {
        final action = await bhpanActionSheet(
          context,
          item: item,
          actions: _actionsFor(item),
          enabled: _actionEnabled,
          location: _locationText,
          boundary: _dialogScope,
        );
        if (action != null && mounted) await _action(action, item);
      },
    );
  }
}
