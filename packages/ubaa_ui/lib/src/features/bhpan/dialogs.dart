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
}) => showDialog<String>(
  context: context,
  builder: (_) => UiScopeBoundary(
    generation: scope,
    child: _TextDialog(title: title, label: label, initial: initial),
  ),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.initial,
  });
  final String title, label, initial;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final _text = TextEditingController(text: widget.initial);
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
      FilledButton(onPressed: _submit, child: const Text('继续')),
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('接收分享'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _link,
          decoration: const InputDecoration(labelText: '北航云盘分享链接或标识'),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          decoration: const InputDecoration(labelText: '提取密码（如有）'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_link.text.trim().isNotEmpty)
            Navigator.pop(context, (
              _link.text.trim(),
              _password.text.isEmpty ? null : _password.text,
            ));
        },
        child: const Text('打开分享'),
      ),
    ],
  );
}

Future<BhpanShareSettings?> bhpanShareDialog(
  BuildContext context, {
  required ValueListenable<int> scope,
  required String title,
  BhpanShare? existing,
}) => showDialog<BhpanShareSettings>(
  context: context,
  builder: (_) => UiScopeBoundary(
    generation: scope,
    child: _ShareDialog(title: title, existing: existing),
  ),
);

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.title, this.existing});
  final String title;
  final BhpanShare? existing;
  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late final _title = TextEditingController(text: widget.title);
  late final _expires = TextEditingController(
    text: widget.existing?.expiresAt ?? '1970-01-01T08:00:00+08:00',
  );
  late final _limit = TextEditingController(
    text: '${widget.existing?.limitedTimes ?? -1}',
  );
  final _password = TextEditingController();
  late final _permissions = <BhpanPermission>{
    ...?widget.existing?.permissions,
    if (widget.existing == null) ...[
      BhpanPermission.display,
      BhpanPermission.download,
    ],
  };
  String? _error;
  @override
  void dispose() {
    for (final c in [_title, _expires, _limit, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? '创建分享' : '更新分享'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: '分享标题'),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: widget.existing == null
                    ? '提取密码（可留空）'
                    : '重新设置密码（留空取消密码）',
              ),
            ),
            TextField(
              controller: _expires,
              decoration: const InputDecoration(
                labelText: '有效期（RFC 3339）',
                helperText: '1970-01-01T08:00:00+08:00 表示不过期',
              ),
            ),
            TextField(
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              decoration: const InputDecoration(labelText: '访问次数，-1 表示不限'),
            ),
            for (final permission in BhpanPermission.values)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(switch (permission) {
                  BhpanPermission.display => '显示',
                  BhpanPermission.preview => '允许预览',
                  BhpanPermission.download => '允许下载',
                  BhpanPermission.create => '允许新建',
                  BhpanPermission.modify => '允许修改',
                }),
                value: _permissions.contains(permission),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _permissions.add(permission);
                  } else {
                    _permissions.remove(permission);
                  }
                }),
              ),
            if (_error case final error?)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('继续确认')),
    ],
  );
  void _submit() {
    final limit = int.tryParse(_limit.text);
    if (_title.text.trim().isEmpty ||
        limit == null ||
        (limit < 1 && limit != -1) ||
        DateTime.tryParse(_expires.text) == null ||
        _permissions.isEmpty) {
      setState(() => _error = '请检查标题、有效期、次数和权限');
      return;
    }
    Navigator.pop(
      context,
      BhpanShareSettings(
        title: _title.text,
        expiresAt: _expires.text,
        password: _password.text,
        limitedTimes: limit,
        permissions: _permissions.toList(),
      ),
    );
  }
}

Future<BhpanItem?> bhpanDestination(
  BuildContext context,
  BhpanService service, {
  required ValueListenable<int> scope,
}) => showDialog<BhpanItem>(
  context: context,
  builder: (_) => UiScopeBoundary(
    generation: scope,
    child: _Destination(service: service),
  ),
);

class _Destination extends StatefulWidget {
  const _Destination({required this.service});
  final BhpanService service;
  @override
  State<_Destination> createState() => _DestinationState();
}

class _DestinationState extends State<_Destination> {
  final _trail = <BhpanItem>[];
  List<BhpanItem> _folders = [];
  String? _error;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([BhpanItem? target]) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.read(
        target == null
            ? const BhpanRead(BhpanReadView.personalRoot)
            : BhpanRead(BhpanReadView.directory, target: target.handle),
      );
      if (!mounted) return;
      setState(
        () => _folders = page.items
            .where((i) => i.isFolder && i.scope == BhpanScope.personal)
            .toList(),
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = e is UiError ? e.message : '目录读取失败');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择个人目的目录'),
    content: SizedBox(
      width: 420,
      height: 360,
      child: Column(
        children: [
          if (_trail.isNotEmpty)
            ListTile(
              leading: IconButton(
                tooltip: '上一级',
                onPressed: _loading
                    ? null
                    : () {
                        _trail.removeLast();
                        _load(_trail.lastOrNull);
                      },
                icon: const Icon(Icons.arrow_back),
              ),
              title: Text(_trail.last.name),
            ),
          if (_loading) const LinearProgressIndicator(),
          if (_error case final error?) Text(error),
          Expanded(
            child: ListView(
              children: [
                for (final folder in _folders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder.name),
                    onTap: _loading
                        ? null
                        : () {
                            _trail.add(folder);
                            _load(folder);
                          },
                  ),
              ],
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
        onPressed: _loading || _error != null || _trail.isEmpty
            ? null
            : () => Navigator.pop(context, _trail.last),
        child: const Text('选择此目录'),
      ),
    ],
  );
}
