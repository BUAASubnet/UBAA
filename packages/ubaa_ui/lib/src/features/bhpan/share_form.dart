import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../shared/dialogs/scope_boundary.dart';

/// 来源用该时刻表示「不过期」。
const bhpanNeverExpires = '1970-01-01T08:00:00+08:00';

/// 创建或修改分享的全屏表单，返回用户确认的设置。
Future<BhpanShareSettings?> bhpanShareDialog(
  BuildContext context, {
  required ValueListenable<int> scope,
  required String title,
  BhpanShare? existing,
  bool isFolder = false,
}) => Navigator.of(context).push<BhpanShareSettings>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => UiScopeBoundary(
      generation: scope,
      child: _ShareForm(title: title, existing: existing, isFolder: isFolder),
    ),
  ),
);

enum _Expiry { never, day, week, month, custom }

enum _PasswordMode { keep, change, none }

String _campusRfc3339(DateTime campus) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${campus.year}-${two(campus.month)}-${two(campus.day)}T${two(campus.hour)}:${two(campus.minute)}:${two(campus.second)}+08:00';
}

DateTime _campusNow() => DateTime.now().toUtc().add(const Duration(hours: 8));

class _ShareForm extends StatefulWidget {
  const _ShareForm({
    required this.title,
    required this.existing,
    required this.isFolder,
  });
  final String title;
  final BhpanShare? existing;
  final bool isFolder;
  @override
  State<_ShareForm> createState() => _ShareFormState();
}

class _ShareFormState extends State<_ShareForm> {
  late final _title = TextEditingController(
    text: widget.existing?.title ?? widget.title,
  );
  final _password = TextEditingController();
  late _PasswordMode _passwordMode = widget.existing?.passwordRequired == true
      ? _PasswordMode.keep
      : _PasswordMode.none;
  _Expiry _expiry = _Expiry.never;

  /// 自定义到期日（校园日期，当天 23:59:59 失效）。
  DateTime? _customDay;
  late bool _unlimited = (widget.existing?.limitedTimes ?? -1) == -1;
  late int _times = switch (widget.existing?.limitedTimes) {
    final t? when t > 0 => t,
    _ => 10,
  };
  late final _permissions = <BhpanPermission>{
    ...?widget.existing?.permissions,
    if (widget.existing == null) ...[
      BhpanPermission.preview,
      BhpanPermission.download,
    ],
  };
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final raw = widget.existing?.expiresAt;
    if (raw != null && raw != bhpanNeverExpires) {
      final time = DateTime.tryParse(raw);
      if (time != null) {
        final campus = time.toUtc().add(const Duration(hours: 8));
        _expiry = _Expiry.custom;
        _customDay = DateTime(campus.year, campus.month, campus.day);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _password.dispose();
    super.dispose();
  }

  String? get _expiresAt {
    final now = _campusNow();
    DateTime endOf(DateTime day) =>
        DateTime(day.year, day.month, day.day, 23, 59, 59);
    return switch (_expiry) {
      _Expiry.never => bhpanNeverExpires,
      _Expiry.day => _campusRfc3339(now.add(const Duration(days: 1))),
      _Expiry.week => _campusRfc3339(now.add(const Duration(days: 7))),
      _Expiry.month => _campusRfc3339(now.add(const Duration(days: 30))),
      _Expiry.custom =>
        _customDay == null ? null : _campusRfc3339(endOf(_customDay!)),
    };
  }

  Future<void> _pickDay() async {
    final now = _campusNow();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _customDay != null && !_customDay!.isBefore(today)
          ? _customDay!
          : today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 3650)),
      helpText: '选择到期日期',
    );
    if (picked != null && mounted)
      setState(() {
        _customDay = picked;
        _expiry = _Expiry.custom;
      });
  }

  void _submit() {
    final expiresAt = _expiresAt;
    final password = _password.text;
    final error = _title.text.trim().isEmpty
        ? '请填写分享标题'
        : expiresAt == null
        ? '请选择到期日期'
        : _passwordMode == _PasswordMode.change && password.isEmpty
        ? '请填写提取码'
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(
      context,
      BhpanShareSettings(
        title: _title.text.trim(),
        expiresAt: expiresAt!,
        password: _passwordMode == _PasswordMode.change ? password : '',
        keepPassword: _passwordMode == _PasswordMode.keep,
        limitedTimes: _unlimited ? -1 : _times,
        // 「显示」是来源要求的基础权限，始终随分享提交，不单独展示。
        permissions: {BhpanPermission.display, ..._permissions}.toList(),
      ),
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  Widget _permission(BhpanPermission p, String title, String subtitle) =>
      SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        value: _permissions.contains(p),
        onChanged: (on) => setState(() {
          if (on) {
            _permissions.add(p);
          } else {
            _permissions.remove(p);
          }
        }),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final day = _customDay;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '取消',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: Text(_editing ? '分享设置' : '创建分享'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: '分享标题',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          _section('提取码'),
          if (_editing && widget.existing!.passwordRequired)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<_PasswordMode>(
                segments: const [
                  ButtonSegment(
                    value: _PasswordMode.keep,
                    label: Text('保留原提取码'),
                  ),
                  ButtonSegment(value: _PasswordMode.change, label: Text('修改')),
                  ButtonSegment(value: _PasswordMode.none, label: Text('不需要')),
                ],
                selected: {_passwordMode},
                showSelectedIcon: false,
                onSelectionChanged: (v) =>
                    setState(() => _passwordMode = v.first),
              ),
            )
          else
            SwitchListTile(
              title: const Text('需要提取码'),
              subtitle: const Text('打开链接时需要输入提取码'),
              value: _passwordMode == _PasswordMode.change,
              onChanged: (on) => setState(
                () => _passwordMode = on
                    ? _PasswordMode.change
                    : _PasswordMode.none,
              ),
            ),
          if (_passwordMode == _PasswordMode.change)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _password,
                enableSuggestions: false,
                autocorrect: false,
                keyboardType: TextInputType.visiblePassword,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                decoration: const InputDecoration(
                  labelText: '提取码',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          _section('有效期'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, label) in const [
                  (_Expiry.never, '永久有效'),
                  (_Expiry.day, '1 天'),
                  (_Expiry.week, '7 天'),
                  (_Expiry.month, '30 天'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _expiry == value,
                    onSelected: (_) => setState(() => _expiry = value),
                  ),
                ChoiceChip(
                  avatar: const Icon(Icons.event, size: 18),
                  label: Text(
                    day == null || _expiry != _Expiry.custom
                        ? '自定义'
                        : '${day.year}年${day.month}月${day.day}日',
                  ),
                  selected: _expiry == _Expiry.custom,
                  onSelected: (_) => _pickDay(),
                ),
              ],
            ),
          ),
          _section('访问次数'),
          SwitchListTile(
            title: const Text('不限次数'),
            value: _unlimited,
            onChanged: (on) => setState(() => _unlimited = on),
          ),
          if (!_unlimited)
            ListTile(
              title: const Text('最多访问'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.outlined(
                    tooltip: '减少',
                    onPressed: _times > 1
                        ? () => setState(() => _times--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '$_times 次',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: '增加',
                    onPressed: _times < 9999
                        ? () => setState(() => _times++)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
          _section('访问者可以'),
          _permission(BhpanPermission.preview, '在线预览', '在浏览器里直接查看文件'),
          _permission(BhpanPermission.download, '下载', '把文件保存到自己的设备'),
          if (widget.isFolder || _editing)
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: const Text('更多权限'),
                subtitle: const Text('仅对文件夹分享有效'),
                initiallyExpanded:
                    _permissions.contains(BhpanPermission.create) ||
                    _permissions.contains(BhpanPermission.modify),
                children: [
                  _permission(BhpanPermission.create, '上传', '向分享的文件夹添加文件'),
                  _permission(BhpanPermission.modify, '修改', '重命名或替换文件夹里的文件'),
                ],
              ),
            ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Text(error, style: TextStyle(color: colors.error)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _submit,
            child: Text(_editing ? '保存设置' : '创建链接'),
          ),
        ),
      ),
    );
  }
}
