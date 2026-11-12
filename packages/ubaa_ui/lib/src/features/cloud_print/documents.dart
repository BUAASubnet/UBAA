part of 'view.dart';

typedef _Transfer = ({String name, String message, bool ok});

enum _FileAction { preview, download, select }

class _Documents extends StatefulWidget {
  const _Documents({
    super.key,
    required this.service,
    required this.scans,
    required this.pickFiles,
    required this.pickFolder,
    required this.previewPdf,
    required this.renderPdf,
    required this.onBusy,
  });
  final CloudPrintService service;
  final bool scans;
  final Future<List<PrintSource>> Function()? pickFiles;
  final Future<PrintDownloadFolder?> Function(bool Function())? pickFolder;
  final PrintPdfPreview? previewPdf;
  final PrintPdfRenderer? renderPdf;
  final ValueChanged<bool> onBusy;

  @override
  State<_Documents> createState() => _DocumentsState();
}

class _DocumentsState extends State<_Documents> {
  late Future<List<PrintDocument>> _read = _list();
  final _selected = <String>{};
  String? _activity;
  double? _progress;
  bool _newestFirst = true;
  bool _selecting = false;
  bool _canSelect = false;
  bool _loading = true;

  bool get _busy => _activity != null;
  bool get _showUpload =>
      !widget.scans && widget.pickFiles != null && !_selecting;
  bool _current() => mounted && widget.service.isCurrent;
  Future<List<PrintDocument>> _list() {
    _loading = true;
    _canSelect = false;
    final pending = Future.sync(
      () => widget.service.documents(scans: widget.scans),
    );
    void finish(bool canSelect) {
      if (!mounted || !identical(_read, pending)) return;
      setState(() {
        _loading = false;
        _canSelect = canSelect;
      });
    }

    unawaited(
      pending.then<void>(
        (files) => finish(files.any((file) => !file.expired)),
        onError: (Object _, StackTrace _) => finish(false),
      ),
    );
    return pending;
  }

  void _reload() => setState(() {
    _selected.clear();
    _selecting = false;
    _read = _list();
  });

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _activity = label);
    widget.onBusy(true);
    try {
      await action();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_error(error))));
      if (error is UiError && error.code == UbaaErrorCode.outcomeUnknown) {
        _reload();
      }
    } finally {
      if (mounted) {
        setState(() {
          _activity = null;
          _progress = null;
        });
        widget.onBusy(false);
      }
    }
  }

  void _results(List<_Transfer> results) {
    if (!_current() || results.isEmpty) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(
            '成功 ${results.where((entry) => entry.ok).length} / ${results.length}',
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in results)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.name),
                  subtitle: Text(entry.message),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  void _writeResults(List<String> names, List<UiError?> errors) {
    if (!_current()) return;
    _reload();
    _results([
      for (final (index, name) in names.indexed)
        (
          name: name,
          ok: errors[index] == null,
          message: errors[index]?.message ?? '成功',
        ),
    ]);
  }

  Future<void> _upload() => _run('', () async {
    final files = await widget.pickFiles!();
    try {
      if (!mounted || files.isEmpty) return;
      if (files.length > 20) throw _tooMany;
      final options = await showDialog<PrintOptions>(
        context: context,
        builder: (_) => _UploadDialog(files: files),
      );
      if (options == null || !_current()) return;
      setState(() => _activity = '正在上传 ${files.length} 份文档');
      final results = await widget.service.upload(files, options);
      _writeResults([for (final file in files) file.name], results);
    } finally {
      for (final file in files) {
        try {
          await file.release?.call();
        } on Object {
          /* 继续释放其余文件。 */
        }
      }
    }
  });

  Future<void> _download(List<_DocumentEntry> targets) => _run('', () async {
    final folder = await widget.pickFolder!(_current);
    if (folder == null) return;
    final results = <_Transfer>[];
    try {
      for (final (i, doc) in targets.indexed) {
        if (!mounted) return;
        setState(() {
          _activity = '正在保存第 ${i + 1} / ${targets.length} 份';
          _progress = i / targets.length;
        });
        try {
          final bytes = doc.merged
              ? await widget.service.scanPdf([
                  for (final file in doc.files) file.id,
                ])
              : await widget.service.scan(doc.id);
          if (!_current()) return;
          final saved = await folder.save(doc.name, bytes, _current);
          results.add((name: doc.name, ok: true, message: '已保存为 $saved'));
        } on Object catch (error) {
          results.add((name: doc.name, ok: false, message: _error(error)));
          if (error is UiError &&
              error.code == UbaaErrorCode.operationConflict) {
            break;
          }
        }
      }
    } finally {
      _results(results);
      await folder.close();
    }
  });

  Future<void> _delete(List<PrintDocument> targets) => _run('', () async {
    if (targets.length > 20) throw _tooMany;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          '删除 ${targets.length} 份${widget.scans ? '扫描文档' : '待打印任务'}？',
        ),
        content: Text(targets.map((doc) => doc.name).join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_current()) return;
    setState(() => _activity = '正在删除');
    final results = await widget.service.delete([
      for (final doc in targets) doc.id,
    ], scans: widget.scans);
    _writeResults([for (final doc in targets) doc.name], results);
  });

  void _startPreview(_DocumentEntry entry) {
    if (!_current()) return;
    final scans = widget.scans;
    final service = widget.service;
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => _DocumentPreview(
            entry: entry,
            title: scans
                ? _dateTime(entry.first.date, entry.first.time)
                : entry.name,
            scans: scans,
            readSource: (index) => scans
                ? service.scan(entry.files[index - 1].id)
                : service.preview(entry.id, index),
            isCurrent: _current,
            download: scans && widget.pickFolder != null
                ? () => _download([entry])
                : null,
            previewPdf: widget.previewPdf,
            renderPdf: widget.renderPdf,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_selecting) _toolbar(),
        if (_activity?.isNotEmpty == true)
          Padding(
            padding: UbaaTheme.pageInsets(context, top: 4, bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_activity!),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: _progress),
              ],
            ),
          ),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Load(read: _read, retry: _reload, body: _listBody),
              if (_showUpload)
                ubaaPositionedCreateButton(
                  tooltip: '上传文件',
                  onPressed: _busy ? null : _upload,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbar() => Padding(
    padding: UbaaTheme.pageInsets(context, top: 4, bottom: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: '选择文件',
          onPressed: _busy || !_canSelect
              ? null
              : () => setState(() => _selecting = true),
          icon: const Icon(Icons.checklist),
        ),
        PopupMenuButton<bool>(
          tooltip: '排序',
          enabled: !_busy,
          icon: const Icon(Icons.sort),
          onSelected: (value) => setState(() => _newestFirst = value),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: true,
              checked: _newestFirst,
              child: const Text('从新到旧'),
            ),
            CheckedPopupMenuItem(
              value: false,
              checked: !_newestFirst,
              child: const Text('从旧到新'),
            ),
          ],
        ),
        IconButton(
          tooltip: '刷新列表',
          onPressed: _busy || _loading ? null : _reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
  );

  void _toggle(_DocumentEntry entry) => setState(() {
    _selecting = true;
    if (!_selected.remove(entry.id)) _selected.add(entry.id);
  });

  Widget _listBody(List<PrintDocument> input) {
    final documents =
        (widget.scans
              ? _scanEntries(input)
              : [for (final file in input) _DocumentEntry.single(file)])
          ..sort((a, b) {
            final date = a.first.date.compareTo(b.first.date);
            final order = date == 0
                ? a.first.time
                      .padLeft(6, '0')
                      .compareTo(b.first.time.padLeft(6, '0'))
                : date;
            return _newestFirst ? -order : order;
          });
    final selectable = documents.where((doc) => !doc.expired).toList();
    final selected = selectable
        .where((doc) => _selected.contains(doc.id))
        .toList();
    final all = selected.isNotEmpty && selected.length == selectable.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (documents.isEmpty)
          Expanded(
            child: Center(child: Text(widget.scans ? '暂无扫描文档' : '暂无待打印任务')),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: UbaaTheme.pageInsets(
                context,
                top: 0,
                bottom: _showUpload ? 96 : null,
              ),
              itemCount: documents.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _entryTile(documents[index]),
            ),
          ),
        if (_selecting)
          UiSelectionBar(
            count: selected.length,
            allSelected: all,
            onClear: _busy
                ? null
                : () => setState(() {
                    _selecting = false;
                    _selected.clear();
                  }),
            onToggleAll: _busy
                ? null
                : () => setState(() {
                    if (all) {
                      _selected.clear();
                    } else {
                      _selected.addAll(selectable.map((doc) => doc.id));
                    }
                  }),
            actions: [
              if (widget.scans && widget.pickFolder != null)
                UiSelectionAction(
                  label: '下载',
                  icon: Icons.download_outlined,
                  onPressed: _busy || selected.isEmpty
                      ? null
                      : () => _download(selected),
                ),
              UiSelectionAction(
                label: '删除',
                icon: Icons.delete_outline,
                danger: true,
                onPressed: _busy || selected.isEmpty
                    ? null
                    : () => _delete([
                        for (final entry in selected) ...entry.files,
                      ]),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _entryActions(
    _DocumentEntry entry,
    String title,
    String meta, {
    required bool preview,
  }) async {
    final action = await showUiFileActions(
      context,
      name: title,
      meta: meta,
      actions: [
        if (preview)
          const UiFileAction(
            value: _FileAction.preview,
            label: '预览',
            icon: Icons.visibility_outlined,
            quick: true,
          ),
        if (widget.scans && widget.pickFolder != null)
          const UiFileAction(
            value: _FileAction.download,
            label: '下载',
            icon: Icons.download_outlined,
            quick: true,
          ),
        const UiFileAction(
          value: _FileAction.select,
          label: '选择',
          icon: Icons.checklist,
        ),
      ],
    );
    if (!_current() || _busy) return;
    switch (action) {
      case _FileAction.preview:
        _startPreview(entry);
      case _FileAction.download:
        await _download([entry]);
      case _FileAction.select:
        _toggle(entry);
      case null:
        break;
    }
  }

  Widget _entryTile(_DocumentEntry entry) {
    final file = entry.first;
    final preview = widget.scans || (file.pages ?? 0) > 0;
    final time = _dateTime(file.date, file.time);
    final title = widget.scans ? time : entry.name;
    final meta = [
      if (!widget.scans) ...[
        time,
        if (file.pages case final pages?) '$pages 页',
        if (file.copies case final copies?) '$copies 份',
      ],
      if (entry.totalBytes case final bytes?)
        _bytes(bytes)
      else if (widget.scans)
        '大小未知',
      if (file.expired) '已过期',
    ].join(' · ');
    return UiFileTile(
      key: ValueKey(entry.id),
      name: title,
      nameLines: widget.scans ? 1 : 2,
      checkboxLabel: '选择 $title',
      leading: UiFileTypeIcon(
        name: entry.name,
        bottomRight: entry.merged ? _ScanCount(entry.files.length) : null,
      ),
      meta: meta,
      selecting: _selecting,
      selected: _selected.contains(entry.id),
      enabled: !_busy && !file.expired,
      onTap: _selecting
          ? () => _toggle(entry)
          : preview
          ? () => _startPreview(entry)
          : null,
      onLongPress: () => _toggle(entry),
      onMore: file.expired
          ? null
          : () => _entryActions(entry, title, meta, preview: preview),
    );
  }
}

class _ScanCount extends StatelessWidget {
  const _ScanCount(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? Colors.white : Colors.black,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              '$count',
              semanticsLabel: '$count 份扫描件',
              style: theme.textTheme.labelSmall?.copyWith(
                color: dark ? Colors.black : Colors.white,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _tooMany = UiError(
  code: UbaaErrorCode.invalidInput,
  title: '文件数量过多',
  message: '每批最多操作 20 份，请分批选择',
);
