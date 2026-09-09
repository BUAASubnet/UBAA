part of '../widgets.dart';

extension _CgyyFormFields on _CgyyReservationFormState {
  Widget _information() => _section('填写预约信息', [
    _field(
      phone,
      '联系电话',
      (s) => draft.phone = s,
      keyboard: TextInputType.phone,
    ),
    const SizedBox(height: 12),
    _field(theme, '预约主题', (s) => draft.theme = s),
    const SizedBox(height: 12),
    if (loading) const LinearProgressIndicator(),
    if (loadError case final e?)
      FriendlyErrorCard(error: e, onRetry: () => _loadPurposes(true)),
    OutlinedButton(
      onPressed: loading ? null : _choosePurpose,
      child: Text(
        draft.manual
            ? '用途编号 ${draft.manualPurpose}'
            : options.where((p) => p.key == draft.purpose).firstOrNull?.name ??
                  '选择活动类型',
      ),
    ),
    if (options.any((p) => p.isStaticFallback))
      Text('活动类型来自本地冻结回退列表。', style: Theme.of(context).textTheme.bodySmall),
    const SizedBox(height: 12),
    _field(
      people,
      '参与人数',
      (s) => draft.people = s,
      keyboard: TextInputType.number,
    ),
    const SizedBox(height: 12),
    _field(content, '活动内容', (s) => draft.content = s, lines: 3),
    const SizedBox(height: 12),
    _field(joiners, '参与人说明', (s) => draft.joiners = s, lines: 2),
  ]);

  Widget _field(
    TextEditingController controller,
    String label,
    ValueChanged<String> changed, {
    TextInputType? keyboard,
    int lines = 1,
  }) => TextField(
    controller: controller,
    onChanged: changed,
    keyboardType: keyboard,
    minLines: lines,
    maxLines: lines == 1 ? 1 : null,
    textInputAction: lines == 1
        ? TextInputAction.next
        : TextInputAction.newline,
    decoration: InputDecoration(labelText: label),
  );

  Future<void> _choosePurpose() async {
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('选择活动类型'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading) const LinearProgressIndicator(),
                  if (!loading && options.isEmpty)
                    const Text('暂无可选活动类型，可重试或手动填写已知编号。'),
                  for (final p in options)
                    ListTile(
                      title: Text(p.name),
                      trailing: !draft.manual && p.key == draft.purpose
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.of(context).pop(p.key),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (widget.data.loadPurposes != null)
              TextButton(
                onPressed: loading
                    ? null
                    : () async {
                        final pending = _loadPurposes(true);
                        refresh(() {});
                        await pending;
                        if (dialogContext.mounted) refresh(() {});
                      },
                child: const Text('刷新活动类型'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(-1),
              child: const Text('手动填写'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || draft.generation != generation || value == null) return;
    if (value == -1) {
      await _manualPurpose();
    } else {
      _setPurpose(value);
    }
  }

  Future<void> _manualPurpose() async {
    final value = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动填写用途编号'),
        content: _field(
          purpose,
          '用途编号',
          (s) => draft.manualPurpose = s,
          keyboard: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('使用编号'),
          ),
        ],
      ),
    );
    if (!mounted || draft.generation != generation || value != true) return;
    _setManual(true);
  }
}
