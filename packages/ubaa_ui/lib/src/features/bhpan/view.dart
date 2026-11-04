import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'dialogs.dart';
import '../../shared/dialogs/scope_boundary.dart';

class BhpanAccess {
  const BhpanAccess({this.service, this.runWrite, this.pickFile});
  final BhpanService? service;
  final Future<WriteOutcome?> Function(BhpanMutation)? runWrite;
  final Future<BhpanLocalFile?> Function()? pickFile;
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
        await _transferLimit();
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
    _query = const BhpanRead(BhpanReadView.personalRoot);
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

  Future<void> _upload() async {
    final service = _service, pick = widget.access.pickFile;
    if (service == null ||
        pick == null ||
        _trail.isEmpty ||
        _trail.last.scope != BhpanScope.personal) {
      await _transferLimit();
      return;
    }
    final generation = _generation, parent = _trail.last;
    Timer? timer;
    try {
      final source = await pick();
      if (!_current(generation) || source == null) return;
      final transfer = service.createTransfer();
      _transfer = transfer;
      Future<void> update() async {
        final progress = await transfer.progress();
        if (mounted && identical(_transfer, transfer))
          setState(() => _progress = progress);
      }

      _progressTimer?.cancel();
      timer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => unawaited(update()),
      );
      _progressTimer = timer;
      await _mutate(
        BhpanMutation(
          BhpanMutationKind.uploadFast,
          target: parent.handle,
          source: source,
          transfer: transfer,
        ),
      );
      await update();
    } on Object catch (e) {
      if (mounted && identical(service, _service))
        setState(() => _notice = _message(e));
    } finally {
      timer?.cancel();
      if (identical(_progressTimer, timer)) _progressTimer = null;
    }
  }

  Future<void> _transferLimit() async {
    await showDialog<void>(
      context: context,
      builder: (c) => _dialogScope(
        AlertDialog(
          title: const Text('文件传输能力'),
          content: const Text(
            '当前版本仅支持个人目录中可秒传的文件。普通与分片上传、文件内容下载、目录和多项打包下载暂不可用，分享上传也暂不可用。',
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

  @override
  Widget build(BuildContext context) {
    if (_service == null) return const Center(child: Text('当前客户端未提供北航云盘能力'));
    final items =
        _page?.items
            .where((i) => i.name.toLowerCase().contains(_filter.toLowerCase()))
            .toList() ??
        [];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PopupMenuButton<BhpanRootKind>(
                enabled: !_loading && !_working,
                onSelected: _root,
                itemBuilder: (_) => [
                  for (final kind in BhpanRootKind.values)
                    PopupMenuItem(
                      value: kind,
                      child: Text(switch (kind) {
                        BhpanRootKind.all => '全部文档库',
                        BhpanRootKind.personal => '个人文档库',
                        BhpanRootKind.shared => '共享文档库',
                        BhpanRootKind.department => '部门文档库',
                        BhpanRootKind.group => '群组文档库',
                      }),
                    ),
                ],
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('文档库 ▾'),
                ),
              ),
              TextButton.icon(
                onPressed: _loading || _working
                    ? null
                    : () {
                        _trail.clear();
                        _query = const BhpanRead(BhpanReadView.recycle);
                        _load();
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('回收站'),
              ),
              TextButton.icon(
                onPressed: _loading || _working
                    ? null
                    : () => _load(shares: true),
                icon: const Icon(Icons.link),
                label: const Text('分享管理'),
              ),
              TextButton(
                onPressed: _loading || _working ? null : _receivedShare,
                child: const Text('接收分享'),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading || _working
                    ? null
                    : () => _load(shares: _shares != null),
                icon: const Icon(Icons.refresh),
              ),
              if (_trail.isNotEmpty &&
                  _trail.last.scope == BhpanScope.personal &&
                  _shares == null &&
                  _query.view == BhpanReadView.directory)
                FilledButton.tonalIcon(
                  onPressed: _writable ? _newFolder : null,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('新建'),
                ),
              OutlinedButton.icon(
                onPressed: _loading || _working ? null : _upload,
                icon: const Icon(Icons.upload_file),
                label: const Text('上传'),
              ),
              TextButton(onPressed: _transferLimit, child: const Text('传输')),
            ],
          ),
        ),
        if (_trail.isNotEmpty && _shares == null)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TextButton(
                  onPressed: _loading || _working
                      ? null
                      : () => _root(BhpanRootKind.personal),
                  child: const Text('文档库'),
                ),
                for (final (index, folder) in _trail.indexed)
                  TextButton(
                    onPressed: _loading || _working
                        ? null
                        : () {
                            _trail.removeRange(index + 1, _trail.length);
                            _query = BhpanRead(
                              BhpanReadView.directory,
                              target: folder.handle,
                            );
                            _load();
                          },
                    child: Text('› ${folder.name}'),
                  ),
              ],
            ),
          ),
        if (_shares == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: '筛选当前已加载名称',
                prefixIcon: Icon(Icons.filter_list),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        if (_selected.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              Text('已选择 ${_selected.length} 项'),
              TextButton(
                onPressed: _writable
                    ? () => _batch(
                        _query.view == BhpanReadView.recycle ? '恢复' : '移入回收站',
                      )
                    : null,
                child: Text(
                  _query.view == BhpanReadView.recycle ? '逐项恢复' : '逐项移入回收站',
                ),
              ),
              if (_query.view == BhpanReadView.recycle)
                TextButton(
                  onPressed: _writable ? () => _batch('永久删除') : null,
                  child: const Text('逐项永久删除'),
                ),
              TextButton(onPressed: _transferLimit, child: const Text('打包下载')),
            ],
          ),
        if (_loading || _working) const LinearProgressIndicator(),
        if (_progress case final progress?)
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: Text(switch (progress.phase) {
              BhpanTransferPhase.queued => '排队',
              BhpanTransferPhase.hashingMini => '计算秒传检查摘要',
              BhpanTransferPhase.hashingFull => '计算完整文件摘要',
              BhpanTransferPhase.checking => '检查秒传',
              BhpanTransferPhase.awaitingConfirmation => '等待上传确认',
              BhpanTransferPhase.submitting => '正在提交',
              BhpanTransferPhase.completed => '上传完成',
              BhpanTransferPhase.cancelled => '任务已取消',
              BhpanTransferPhase.failed => '任务失败',
              BhpanTransferPhase.outcomeUnknown => '上传结果待核对',
              BhpanTransferPhase.blocked => '传输协议尚缺证据',
            }),
            subtitle: Text(
              '${bhpanBytes(progress.bytes)} / ${bhpanBytes(progress.total)}',
            ),
            trailing: TextButton(
              onPressed:
                  const {
                    BhpanTransferPhase.queued,
                    BhpanTransferPhase.hashingMini,
                    BhpanTransferPhase.hashingFull,
                    BhpanTransferPhase.checking,
                    BhpanTransferPhase.awaitingConfirmation,
                  }.contains(progress.phase)
                  ? () => _transfer?.cancel()
                  : null,
              child: const Text('取消任务'),
            ),
          ),
        if (_batchResults.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final (name, status) in _batchResults)
                  Text('$name：$status'),
              ],
            ),
          ),
        if (_notice case final notice?)
          Padding(padding: const EdgeInsets.all(12), child: Text(notice)),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(error),
                TextButton(
                  onPressed: _loading ? null : () => _load(reconnect: true),
                  child: const Text('重新连接个人网盘'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _shares != null
              ? _shareList()
              : items.isEmpty && !_loading
              ? Center(
                  child: Text(
                    _error != null
                        ? '未取得目录内容'
                        : _filter.isNotEmpty
                        ? '已加载列表中没有匹配名称'
                        : '当前已读取范围没有条目',
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (c, index) => _row(items[index]),
                ),
        ),
        if (_page case final page?)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              page.range == BhpanListRange.firstHundred
                  ? '回收站首批最多 100 项，完整范围待验证'
                  : '显示已读取范围，完整列表范围未知',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _row(BhpanItem item) {
    final recycle = item.scope == BhpanScope.recycle;
    final actions = recycle
        ? ['恢复', '永久删除']
        : item.scope == BhpanScope.receivedShare
        ? ['属性', '下载', '另存到网盘']
        : ['属性', '重命名', '移动', '复制', '下载', '分享', '分享记录', '移入回收站'];
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: _selected.contains(item.handle),
            onChanged: _loading || _working
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      _selected.add(item.handle);
                    } else {
                      _selected.remove(item.handle);
                    }
                  }),
          ),
          Icon(
            item.isFolder
                ? Icons.folder_outlined
                : Icons.insert_drive_file_outlined,
          ),
        ],
      ),
      title: Text(item.name),
      subtitle: Text(
        '${item.isFolder ? '文件夹' : bhpanBytes(item.bytes ?? 0)}${item.modifiedAt == null ? '' : ' · ${bhpanDate(item.modifiedAt!)}'}',
      ),
      onTap: _loading || _working
          ? null
          : () => item.isFolder && !recycle ? _open(item) : _action('属性', item),
      trailing: PopupMenuButton<String>(
        enabled: _writable,
        onSelected: (a) => _action(a, item),
        itemBuilder: (_) => [
          for (final a in actions) PopupMenuItem(value: a, child: Text(a)),
        ],
      ),
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

String bhpanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  if (bytes < 1024 * 1024 * 1024)
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GiB';
}

String bhpanDate(DateTime time) {
  final d = time.toUtc().add(const Duration(hours: 8));
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
