import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../shared/dialogs/scope_boundary.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

Future<String?> bhpanText(
  BuildContext context, {
  required ValueListenable<int> scope,
  required String title,
  required String label,
  String initial = '',
  String action = '继续',
}) => showDialog<String>(
  context: context,
  builder: (_) => UiScopeBoundary(
    generation: scope,
    child: _TextDialog(
      title: title,
      label: label,
      initial: initial,
      action: action,
    ),
  ),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
  });
  final String title, label, initial, action;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  // 重命名时默认只选中扩展名之前的部分，方便直接改名。
  late final _text = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: switch (widget.initial.lastIndexOf('.')) {
        > 0 && final dot => dot,
        _ => widget.initial.length,
      },
    );
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      decoration: InputDecoration(labelText: widget.label),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: Text(widget.action)),
    ],
  );
  void _submit() {
    if (_text.text.trim().isNotEmpty) Navigator.pop(context, _text.text);
  }
}

Future<(String, String?)?> bhpanOpenShareDialog(
  BuildContext context, {
  required ValueListenable<int> scope,
}) => showDialog<(String, String?)>(
  context: context,
  builder: (_) =>
      UiScopeBoundary(generation: scope, child: const _OpenShareDialog()),
);

/// 从粘贴的整段文字里拆出链接与提取码，例如「链接：https://… 提取码：abcd」。
(String, String?) bhpanParseShareText(String text) {
  final link = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
  final code = RegExp(
    r'(?:提取码|提取密码|密码|访问码)\s*[:：]?\s*([A-Za-z0-9]+)',
  ).firstMatch(text)?.group(1);
  final cleaned = link?.replaceAll(RegExp(r'[，。,;；)）]+$'), '');
  return (cleaned ?? text.trim(), code);
}

class _OpenShareDialog extends StatefulWidget {
  const _OpenShareDialog();
  @override
  State<_OpenShareDialog> createState() => _OpenShareDialogState();
}

class _OpenShareDialogState extends State<_OpenShareDialog> {
  final _link = TextEditingController(), _password = TextEditingController();
  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    super.dispose();
  }

  void _apply(String text) {
    final (link, code) = bhpanParseShareText(text);
    if (link != text.trim() || code != null) {
      _link.text = link;
      if (code != null) _password.text = code;
    }
    setState(() {});
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && mounted) _apply(text);
  }

  void _submit() {
    if (_link.text.trim().isEmpty) return;
    Navigator.pop(context, (
      _link.text.trim(),
      _password.text.isEmpty ? null : _password.text,
    ));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('打开分享链接'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _link,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: 3,
            onChanged: (text) {
              if (text.contains('码')) _apply(text);
            },
            decoration: InputDecoration(
              labelText: '分享链接',
              hintText: '可直接粘贴含提取码的整段文字',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '从剪贴板粘贴',
                onPressed: _paste,
                icon: const Icon(Icons.content_paste),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            keyboardType: TextInputType.visiblePassword,
            enableSuggestions: false,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: '提取码（没有可不填）',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _link.text.trim().isEmpty ? null : _submit,
        child: const Text('打开'),
      ),
    ],
  );
}

Future<BhpanItem?> bhpanDestination(
  BuildContext context,
  BhpanService service, {
  required ValueListenable<int> scope,
  String title = '选择目标文件夹',
  String action = '选择此文件夹',
  Set<String> exclude = const {},
  List<BhpanItem>? start,
  String? disabledTarget,
}) => Navigator.of(context).push<BhpanItem>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => UiScopeBoundary(
      generation: scope,
      child: _Destination(
        service: service,
        title: title,
        action: action,
        exclude: exclude,
        start: start,
        disabledTarget: disabledTarget,
      ),
    ),
  ),
);

/// 目标文件夹选择：从当前位置开始，排除正在移动的条目，原目录不能作为移动目标。
class _Destination extends StatefulWidget {
  const _Destination({
    required this.service,
    required this.title,
    required this.action,
    required this.exclude,
    required this.start,
    required this.disabledTarget,
  });
  final BhpanService service;
  final String title, action;
  final Set<String> exclude;
  final List<BhpanItem>? start;
  final String? disabledTarget;
  @override
  State<_Destination> createState() => _DestinationState();
}

class _DestinationState extends State<_Destination> {
  final _trail = <BhpanItem>[];
  int _baseDepth = 0;
  List<BhpanItem>? _folders;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    final start = widget.start;
    if (start != null && start.isNotEmpty) {
      _trail.addAll(start);
      _baseDepth = 1;
    }
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _folders = null;
    });
    try {
      final target = _trail.lastOrNull;
      var page = await widget.service.read(
        target == null
            ? const BhpanRead(BhpanReadView.personalRoot)
            : BhpanRead(BhpanReadView.directory, target: target.handle),
      );
      if (target == null &&
          page.items.length == 1 &&
          page.items.single.isFolder) {
        // 与主界面一致：自动进入唯一的个人根目录。
        _trail.add(page.items.single);
        _baseDepth = 1;
        page = await widget.service.read(
          BhpanRead(BhpanReadView.directory, target: page.items.single.handle),
        );
      }
      if (!mounted || generation != _generation) return;
      setState(
        () => _folders =
            page.items
                .where(
                  (i) =>
                      i.isFolder &&
                      i.scope == BhpanScope.personal &&
                      !widget.exclude.contains(i.handle),
                )
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              ),
      );
    } on Object catch (e) {
      if (mounted && generation == _generation)
        setState(() => _error = e is UiError ? e.message : '文件夹读取失败');
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  void _up() {
    if (_trail.length <= _baseDepth) return;
    _trail.removeLast();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = _trail.lastOrNull;
    final names = ['个人文档库', for (final f in _trail.skip(_baseDepth)) f.name];
    final canPick =
        !_loading &&
        _error == null &&
        current != null &&
        current.handle != widget.disabledTarget;
    final folders = _folders;
    return PopScope<BhpanItem>(
      canPop: _trail.length <= _baseDepth,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: '取消',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '上一级',
                    onPressed: _trail.length > _baseDepth && !_loading
                        ? _up
                        : null,
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  Expanded(
                    child: Text(
                      names.join(' / '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                              onPressed: _load,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : folders == null
                  ? const Center(child: CircularProgressIndicator())
                  : folders.isEmpty
                  ? Center(
                      child: Text(
                        '这里没有子文件夹',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  : ListView(
                      children: [
                        for (final folder in folders)
                          ListTile(
                            leading: const Icon(
                              Icons.folder_rounded,
                              color: Color(0xFFF2B53A),
                            ),
                            title: Text(folder.name),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: colors.outline,
                            ),
                            onTap: _loading
                                ? null
                                : () {
                                    _trail.add(folder);
                                    _load();
                                  },
                          ),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (current != null &&
                        current.handle == widget.disabledTarget)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '已经在这个文件夹里了，请选择其他位置',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: canPick
                          ? () => Navigator.pop(context, current)
                          : null,
                      child: Text(widget.action),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
