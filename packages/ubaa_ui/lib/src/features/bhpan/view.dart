import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'chrome.dart';
import 'toolbar.dart';
import 'dialogs.dart';
import 'format.dart';
import 'transfer_view.dart';
import '../../shared/dialogs/scope_boundary.dart';

class BhpanAccess {
  const BhpanAccess({
    this.service,
    this.runWrite,
    this.pickFile,
    this.pickDownload,
  });
  final BhpanService? service;
  final Future<WriteOutcome?> Function(BhpanMutation)? runWrite;
  final Future<BhpanLocalFile?> Function()? pickFile;
  final Future<BhpanDownloadDestination?> Function(
    String name,
    bool Function() isCurrent,
  )?
  pickDownload;
}

/// 校园与空间指标共用的云盘页面。
class BhpanView extends StatefulWidget {
  const BhpanView({required this.access, super.key});
  final BhpanAccess access;
  @override
  State<BhpanView> createState() => _BhpanViewState();
}

class _BhpanViewState extends State<BhpanView> {
  BhpanRead _query = const BhpanRead(BhpanReadView.personalRoot);
  final _trail = <BhpanItem>[];
  BhpanPage? _page;
  List<BhpanShare>? _shares;
  String? _error, _notice;
  String _filter = '';
  BhpanRootKind _rootKind = BhpanRootKind.personal;
  bool _searchVisible = false;
  bool _loading = false, _working = false;
  int _generation = 0;
  final _scope = ValueNotifier<int>(0);
  Object? _mutationActivity;
  final _selected = <String>{};
  final _batchResults = <(String, String)>[];
  BhpanTransferTask? _transfer;
  BhpanTransferProgress? _progress;
  Timer? _progressTimer;
  BhpanService? get _service => widget.access.service;
  bool get _writable =>
      widget.access.runWrite != null && !_working && !_loading;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant BhpanView old) {
    super.didUpdateWidget(old);
    if (!identical(old.access.service, _service)) {
      _scope.value++;
      _mutationActivity = null;
      _working = false;
      _transfer?.cancel();
      _progressTimer?.cancel();
      _transfer = null;
      _progress = null;
      _batchResults.clear();
      _generation++;
      _page = null;
      _shares = null;
      _trail.clear();
      _selected.clear();
      _query = const BhpanRead(BhpanReadView.personalRoot);
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _scope.value++;
    _scope.dispose();
    _transfer?.cancel();
    _progressTimer?.cancel();
    _generation++;
    super.dispose();
  }

  Widget _dialogScope(Widget child) =>
      UiScopeBoundary(generation: _scope, child: child);
  bool _current(int generation) => mounted && generation == _generation;
  String _message(Object e) => e is UiError ? e.message : '云盘操作未完成，请检查连接后重试';
  Future<void> _load({bool reconnect = false, bool shares = false}) async {
    final service = _service;
    if (service == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
    });
    try {
      if (reconnect) {
        await service.login();
        _trail.clear();
        _query = const BhpanRead(BhpanReadView.personalRoot);
      }
      if (!_current(generation)) return;
      if (shares) {
        final result = await service.shares();
        if (_current(generation))
          setState(() {
            _shares = result;
            _page = null;
          });
      } else {
        var result = await service.read(_query);
        if (!_current(generation)) return;
        if (_query.view == BhpanReadView.personalRoot &&
            result.items.length == 1) {
          final root = result.items.single;
          _trail
            ..clear()
            ..add(root);
          _query = BhpanRead(BhpanReadView.directory, target: root.handle);
          result = await service.read(_query);
        }
        if (_current(generation))
          setState(() {
            _page = result;
            _shares = null;
          });
      }
    } on Object catch (e) {
      if (_current(generation))
        setState(() {
          _error = _message(e);
          _page = null;
          _shares = null;
        });
    } finally {
      if (_current(generation)) setState(() => _loading = false);
    }
  }

  Future<void> _open(BhpanItem item) async {
    if (!item.isFolder || item.scope == BhpanScope.recycle) return;
    _trail.add(item);
    _query = BhpanRead(BhpanReadView.directory, target: item.handle);
    await _load();
  }

  Future<void> _root(BhpanRootKind kind) async {
    _trail.clear();
    _query = kind == BhpanRootKind.personal
        ? const BhpanRead(BhpanReadView.personalRoot)
        : BhpanRead(BhpanReadView.roots, root: kind);
    await _load();
  }

  Future<WriteOutcome?> _mutate(BhpanMutation request) async {
    final run = widget.access.runWrite;
    if (run == null || _working) return null;
    final generation = _generation;
    final activity = Object();
    _mutationActivity = activity;
    setState(() => _working = true);
    try {
      final result = await run(request);
      if (!_current(generation) || result == null) return null;
      setState(() => _notice = result.message);
      final share = result.result?.bhpanReceipt?.share;
      if (share != null) {
        setState(() {
          _shares = [
            share,
            ...?_shares?.where((old) => old.handle != share.handle),
          ];
          _page = null;
        });
        await _showShare(share);
      } else if (result.error == null ||
          result.error?.code == UbaaErrorCode.outcomeUnknown) {
        await _load(shares: _shares != null);
      }
      return result;
    } on Object catch (e) {
      if (_current(generation)) setState(() => _notice = _message(e));
      return null;
    } finally {
      if (mounted && identical(_mutationActivity, activity))
        setState(() {
          _mutationActivity = null;
          _working = false;
        });
    }
  }

  Future<WriteOutcome?> _action(String action, BhpanItem item) async {
    final service = _service;
    if (service == null) return null;
    final generation = _generation;
    try {
      if (action == '属性') {
        final s = await service.size(item.handle);
        if (!_current(generation)) return null;
        await showDialog<void>(
          context: context,
          builder: (c) => _dialogScope(
            AlertDialog(
              title: Text(item.name),
              content: Text(
                '${s.folders} 个文件夹 · ${s.files} 个文件\n${bhpanBytes(s.bytes)}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        );
        return null;
      }
      if (action == '分享记录') {
        final records = await service.shares(item: item.handle);
        if (_current(generation))
          setState(() {
            _shares = records;
            _page = null;
          });
        return null;
      }
      if (action == '下载') {
        await _download([item]);
        return null;
      }
      if (action == '重命名') {
        final name = await bhpanText(
          context,
          scope: _scope,
          title: '重命名',
          label: '新名称',
          initial: item.name,
        );
        if (!_current(generation) || name == null) return null;
        return _mutate(
          BhpanMutation(
            BhpanMutationKind.rename,
            target: item.handle,
            name: name,
          ),
        );
      }
      if (action == '移动' || action == '复制' || action == '另存到网盘') {
        final dest = await bhpanDestination(context, service, scope: _scope);
        if (!_current(generation) || dest == null) return null;
        return _mutate(
          BhpanMutation(
            action == '移动' ? BhpanMutationKind.move : BhpanMutationKind.copy,
            target: item.handle,
            destination: dest.handle,
          ),
        );
      }
      if (action == '分享') {
        final settings = await bhpanShareDialog(
          context,
          scope: _scope,
          title: item.name,
        );
        if (!_current(generation) || settings == null) return null;
        return _mutate(
          BhpanMutation(
            BhpanMutationKind.createShare,
            target: item.handle,
            settings: settings,
          ),
        );
      }
      final kind = switch (action) {
        '移入回收站' => BhpanMutationKind.recycle,
        '恢复' => BhpanMutationKind.restore,
        _ => BhpanMutationKind.deleteForever,
      };
      return _mutate(BhpanMutation(kind, target: item.handle));
    } on Object catch (e) {
      if (_current(generation)) setState(() => _notice = _message(e));
      return null;
    }
  }

  Future<void> _showShare(BhpanShare s) async {
    final service = _service;
    if (service == null) return;
    final generation = _generation;
    try {
      final link = await service.shareLink(s.handle);
      if (!_current(generation)) return;
      await showDialog<void>(
        context: context,
        builder: (c) => _dialogScope(
          AlertDialog(
            title: Text(s.title),
            content: SelectableText(link),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (c.mounted) Navigator.pop(c);
                },
                child: const Text('复制分享链接'),
              ),
            ],
          ),
        ),
      );
    } on Object catch (e) {
      if (_current(generation)) setState(() => _notice = _message(e));
    }
  }

  Future<void> _shareAction(String action, BhpanShare s) async {
    if (action == '复制链接') {
      await _showShare(s);
      return;
    }
    if (action == '取消分享') {
      await _mutate(
        BhpanMutation(BhpanMutationKind.cancelShare, target: s.handle),
      );
      return;
    }
    final generation = _generation;
    final settings = await bhpanShareDialog(
      context,
      scope: _scope,
      title: s.title,
      existing: s,
    );
    if (!_current(generation) || settings == null) return;
    await _mutate(
      BhpanMutation(
        BhpanMutationKind.updateShare,
        target: s.handle,
        settings: settings,
      ),
    );
  }

  Future<void> _receivedShare() async {
    final generation = _generation;
    final input = await bhpanOpenShareDialog(context, scope: _scope);
    if (!_current(generation) || input == null) return;
    _trail.clear();
    _query = BhpanRead(
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
    );
    if (!_current(generation) || name == null) return;
    await _mutate(
      BhpanMutation(
        BhpanMutationKind.createFolder,
        target: parent.handle,
        name: name,
      ),
    );
  }

  Future<void> Function() _track(BhpanTransferTask transfer) {
    _transfer = transfer;
    Future<void> update() async {
      try {
        final progress = await transfer.progress();
        if (mounted && identical(_transfer, transfer))
          setState(() => _progress = progress);
      } on Object catch (error) {
        transfer.cancel();
        if (mounted && identical(_transfer, transfer))
          setState(() => _notice = _message(error));
      }
    }

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => unawaited(update()),
    );
    return update;
  }

  Future<void> _upload({bool fast = false}) async {
    final service = _service, pick = widget.access.pickFile;
    if (service == null ||
        pick == null ||
        _trail.isEmpty ||
        !_trail.last.isFolder ||
        _trail.last.scope == BhpanScope.recycle)
      return;
    if (fast && _trail.last.scope != BhpanScope.personal) return;
    final generation = _generation, parent = _trail.last;
    BhpanTransferTask? task;
    BhpanLocalFile? selected;
    Future<void> Function()? refresh;
    try {
      final source = await pick();
      selected = source;
      if (!_current(generation) || source == null) return;
      final transfer = service.createTransfer();
      task = transfer;
      // 同一个控制柄贯穿准备、确认和提交。
      refresh = _track(transfer);
      await _mutate(
        BhpanMutation(
          fast ? BhpanMutationKind.uploadFast : BhpanMutationKind.upload,
          target: parent.handle,
          source: source,
          transfer: transfer,
        ),
      );
      await refresh();
    } on Object catch (error) {
      if (mounted && identical(service, _service))
        setState(() => _notice = _message(error));
    } finally {
      try {
        await selected?.release();
      } on Object catch (error) {
        if (_current(generation)) setState(() => _notice = _message(error));
      }
      task?.cancel();
      await refresh?.call();
      if (identical(_transfer, task)) {
        _progressTimer?.cancel();
        _progressTimer = null;
      }
    }
  }

  Future<void> _download(List<BhpanItem> items) async {
    final service = _service, pick = widget.access.pickDownload;
    if (service == null ||
        pick == null ||
        items.isEmpty ||
        _working ||
        _loading)
      return;
    final generation = _generation, activity = Object();
    final base = items.length == 1
        ? items.single.name.replaceAll(RegExp(r'[\\/\r\n]'), '_')
        : '北航云盘下载';
    final batch = items.length != 1 || items.single.isFolder;
    final name = base.trim().isEmpty ? '北航云盘下载' : base;
    final suggested = batch ? '$name.zip' : name;
    BhpanDownloadDestination? destination;
    BhpanTransferTask? task;
    Future<void> Function()? refresh;
    setState(() {
      _working = true;
      _mutationActivity = activity;
      _notice = null;
    });
    try {
      destination = await pick(
        suggested,
        () => _current(generation) && identical(service, _service),
      );
      if (destination == null || !_current(generation)) return;
      final transfer = service.createTransfer();
      task = transfer;
      refresh = _track(transfer);
      final receipt = await service.download(
        items.map((item) => item.handle).toList(),
        name,
        destination.path,
        destination.overwrite,
        transfer,
      );
      if (!_current(generation)) return;
      await destination.deliver(
        () => _current(generation) && identical(service, _service),
      );
      await refresh();
      if (_current(generation))
        setState(() {
          _notice = '已保存 $suggested（${bhpanBytes(receipt.bytes)}）';
          _progress = BhpanTransferProgress(
            phase: BhpanTransferPhase.completed,
            bytes: receipt.bytes,
            total: receipt.bytes,
          );
        });
    } on Object catch (error) {
      if (_current(generation)) setState(() => _notice = _message(error));
    } finally {
      task?.cancel();
      if (identical(_transfer, task)) {
        if (_progress?.phase != BhpanTransferPhase.completed)
          await refresh?.call();
        _progressTimer?.cancel();
        _progressTimer = null;
      }
      try {
        await destination?.discard();
      } on Object catch (error) {
        if (_current(generation)) setState(() => _notice = _message(error));
      }
      if (mounted && identical(_mutationActivity, activity))
        setState(() {
          _working = false;
          _mutationActivity = null;
        });
    }
  }

  Future<void> _batch(String action) async {
    final items =
        _page?.items.where((i) => _selected.contains(i.handle)).toList() ?? [];
    final service = _service;
    _batchResults.clear();
    var stopped = false;
    for (final item in items) {
      if (!mounted || !identical(service, _service)) return;
      if (stopped) {
        _batchResults.add((item.name, '尚未执行'));
        continue;
      }
      final result = await _action(action, item);
      if (!mounted || !identical(service, _service)) return;
      final unknown =
          result?.error?.code == UbaaErrorCode.outcomeUnknown ||
          result?.result?.outcomeUnknown == true;
      final status = unknown
          ? '结果待核对'
          : result == null
          ? '尚未执行'
          : result.error != null || result.result?.success != true
          ? '失败'
          : '已完成';
      _batchResults.add((item.name, status));
      stopped = unknown || result == null;
    }
    if (mounted) setState(() {});
  }

  static const _rootNames = {
    BhpanRootKind.all: '全部文档库',
    BhpanRootKind.personal: '个人文档库',
    BhpanRootKind.shared: '共享文档库',
    BhpanRootKind.department: '部门文档库',
    BhpanRootKind.group: '群组文档库',
  };

  bool get _busy => _loading || _working;
  bool get _inRecycle => _query.view == BhpanReadView.recycle;
  bool get _canUpload =>
      !_busy &&
      widget.access.pickFile != null &&
      widget.access.runWrite != null &&
      _shares == null &&
      _trail.isNotEmpty &&
      _trail.last.isFolder &&
      _trail.last.scope != BhpanScope.recycle;
  bool get _personalFolder =>
      _trail.isNotEmpty &&
      _trail.last.scope == BhpanScope.personal &&
      _shares == null &&
      _query.view == BhpanReadView.directory;

  String get _viewLabel => _shares != null
      ? '分享管理'
      : _inRecycle
      ? '回收站'
      : _rootNames[_rootKind]!;

  void _openRecycle() {
    _trail.clear();
    _selected.clear();
    _query = const BhpanRead(BhpanReadView.recycle);
    _load();
  }

  Widget _toolbar() => BhpanToolbar(
    label: _viewLabel,
    icon: _shares != null
        ? Icons.link
        : _inRecycle
        ? Icons.delete_outline
        : Icons.folder_shared_outlined,
    rootNames: _rootNames,
    current: _shares == null && !_inRecycle ? _rootKind : null,
    busy: _busy,
    showSearch: _shares == null,
    searchVisible: _searchVisible,
    showHome: _shares != null || _inRecycle,
    showFast: _personalFolder && widget.access.pickFile != null,
    fastEnabled: _writable,
    onRoot: (kind) {
      setState(() {
        _rootKind = kind;
        _selected.clear();
      });
      _root(kind);
    },
    onToggleSearch: () => setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) _filter = '';
    }),
    onRefresh: () => _load(shares: _shares != null),
    onMenu: (value) {
      switch (value) {
        case 'recycle':
          _openRecycle();
        case 'shares':
          _selected.clear();
          _load(shares: true);
        case 'received':
          _receivedShare();
        case 'fast':
          _upload(fast: true);
        case 'home':
          setState(() => _rootKind = BhpanRootKind.personal);
          _root(BhpanRootKind.personal);
      }
    },
  );

  Widget _selectionBar() {
    final colors = Theme.of(context).colorScheme;
    final selectedItems =
        _page?.items.where((i) => _selected.contains(i.handle)).toList() ??
        const <BhpanItem>[];
    return Material(
      color: colors.secondaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: '取消选择',
                onPressed: () => setState(_selected.clear),
                icon: const Icon(Icons.close),
              ),
              Expanded(
                child: Text(
                  '已选 ${_selected.length} 项',
                  style: TextStyle(
                    color: colors.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  final all =
                      _page?.items.map((i) => i.handle) ?? const <String>[];
                  if (_selected.length == all.length) {
                    _selected.clear();
                  } else {
                    _selected.addAll(all);
                  }
                }),
                child: const Text('全选'),
              ),
              if (!_inRecycle)
                IconButton(
                  tooltip: '打包下载',
                  onPressed: _busy ? null : () => _download(selectedItems),
                  icon: const Icon(Icons.download_outlined),
                ),
              if (_inRecycle)
                IconButton(
                  tooltip: '逐项恢复',
                  onPressed: _writable ? () => _batch('恢复') : null,
                  icon: const Icon(Icons.restore),
                ),
              IconButton(
                tooltip: _inRecycle ? '逐项永久删除' : '逐项移入回收站',
                onPressed: _writable
                    ? () => _batch(_inRecycle ? '永久删除' : '移入回收站')
                    : null,
                icon: Icon(
                  _inRecycle
                      ? Icons.delete_forever_outlined
                      : Icons.delete_outline,
                  color: colors.error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => _dialogScope(
        SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('上传文件'),
                subtitle: const Text('从本机选择文件上传到当前文件夹'),
                enabled: _canUpload,
                onTap: () => Navigator.pop(context, 'upload'),
              ),
              if (_personalFolder) ...[
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('新建文件夹'),
                  enabled: _writable,
                  onTap: () => Navigator.pop(context, 'folder'),
                ),
                ListTile(
                  leading: const Icon(Icons.bolt_outlined),
                  title: const Text('秒传'),
                  subtitle: const Text('云端已有相同文件时免上传内容'),
                  enabled: _writable,
                  onTap: () => Navigator.pop(context, 'fast'),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'upload':
        await _upload();
      case 'folder':
        await _newFolder();
      case 'fast':
        await _upload(fast: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_service == null) {
      return const BhpanStatePanel(
        icon: Icons.cloud_off_outlined,
        text: '当前客户端未提供北航云盘能力',
      );
    }
    final items =
        _page?.items
            .where((i) => i.name.toLowerCase().contains(_filter.toLowerCase()))
            .toList() ??
        [];
    final selecting = _selected.isNotEmpty;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(),
        if (_trail.isNotEmpty && _shares == null)
          BhpanBreadcrumb(
            rootLabel: _rootNames[_rootKind]!,
            names: [for (final f in _trail) f.name],
            enabled: !_busy,
            onRoot: () => _root(_rootKind),
            onIndex: (index) {
              _trail.removeRange(index + 1, _trail.length);
              _selected.clear();
              _query = BhpanRead(
                BhpanReadView.directory,
                target: _trail[index].handle,
              );
              _load();
            },
          ),
        if (_shares == null && (_searchVisible || _filter.isNotEmpty))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              autoFocus: true,
              hintText: '筛选当前已加载的名称',
              elevation: const WidgetStatePropertyAll(0),
              leading: const Icon(Icons.search),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        SizedBox(
          height: 2,
          child: _busy ? const LinearProgressIndicator() : null,
        ),
        if (_progress case final progress?)
          BhpanProgressTile(progress: progress, onCancel: _transfer?.cancel),
        if (_batchResults.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                for (final (name, status) in _batchResults)
                  Text(
                    '$name：$status',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        if (_notice case final notice?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(notice)),
              ],
            ),
          ),
        Expanded(
          child: _error != null && items.isEmpty
              ? BhpanStatePanel(
                  icon: Icons.cloud_off_outlined,
                  text: _error!,
                  action: '重新连接个人网盘',
                  onAction: _loading ? null : () => _load(reconnect: true),
                )
              : _shares != null
              ? _shareList()
              : items.isEmpty && !_loading
              ? BhpanStatePanel(
                  icon: _filter.isNotEmpty
                      ? Icons.search_off
                      : Icons.folder_open_outlined,
                  text: _filter.isNotEmpty ? '已加载列表中没有匹配名称' : '这个文件夹是空的',
                )
              : RefreshIndicator(
                  onRefresh: () => _load(shares: _shares != null),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.only(bottom: selecting ? 16 : 96),
                    itemCount: items.length + 1,
                    itemBuilder: (c, index) => index == items.length
                        ? _footer(items.length)
                        : _row(items[index], selecting),
                  ),
                ),
        ),
        if (selecting) _selectionBar(),
      ],
    );
    final showFab =
        !selecting &&
        _shares == null &&
        (_canUpload || (_personalFolder && widget.access.runWrite != null));
    return Stack(
      children: [
        Positioned.fill(child: body),
        if (showFab)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              key: const ValueKey('bhpan-create'),
              tooltip: '上传或新建',
              onPressed: _busy ? null : _createSheet,
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  Widget _footer(int count) {
    final page = _page;
    if (page == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        page.range == BhpanListRange.firstHundred
            ? '回收站仅显示前 100 项'
            : '已加载 $count 项',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _row(BhpanItem item, bool selecting) {
    final recycle = item.scope == BhpanScope.recycle;
    final actions = recycle
        ? ['恢复', '永久删除']
        : item.scope == BhpanScope.receivedShare
        ? ['属性', '下载', '另存到网盘']
        : ['属性', '重命名', '移动', '复制', '下载', '分享', '分享记录', '移入回收站'];
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
          : () => item.isFolder && !recycle ? _open(item) : _action('属性', item),
      onLongPress: toggle,
      onMore: () async {
        final action = await bhpanActionSheet(
          context,
          title: item.name,
          item: item,
          actions: actions,
          enabled: (a) => const {'属性', '下载', '分享记录'}.contains(a) || _writable,
          boundary: _dialogScope,
        );
        if (action != null && mounted) await _action(action, item);
      },
    );
  }

  Widget _shareList() => _shares!.isEmpty
      ? const Center(child: Text('当前已读取范围没有分享记录'))
      : ListView(
          children: [
            for (final s in _shares!)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(s.title),
                subtitle: Text(
                  '${s.passwordRequired ? '有提取密码' : '无提取密码'} · ${s.limitedTimes == -1 ? '次数不限' : '限 ${s.limitedTimes} 次'}\n有效期：${s.expiresAt == '1970-01-01T08:00:00+08:00' ? '长期有效' : s.expiresAt}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  enabled: _writable,
                  onSelected: (a) => _shareAction(a, s),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: '复制链接', child: Text('查看与复制链接')),
                    PopupMenuItem(
                      value: '修改',
                      enabled: s.canUpdate,
                      child: const Text('修改设置'),
                    ),
                    const PopupMenuItem(value: '取消分享', child: Text('取消分享')),
                  ],
                ),
              ),
          ],
        );
}
