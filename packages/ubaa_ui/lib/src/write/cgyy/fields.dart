part of 'form.dart';

extension CgyyFormFields on _CgyyReservationFormState {
  Widget _information() => _section('填写预约信息', [
    _field(
      phone,
      '联系电话',
      (s) => draft.phone = s,
      keyboard: TextInputType.phone,
      hint: defaults?.phone,
    ),
    const SizedBox(height: 12),
    _field(theme, '预约主题', (s) => draft.theme = s, hint: defaults?.theme),
    const SizedBox(height: 12),
    if (loadError case final e? when !loading && options.isEmpty)
      FriendlyErrorCard(error: e, onRetry: () => _loadPurposes(true)),
    if (!loading && options.isEmpty && loadError == null)
      TextButton(onPressed: () => _loadPurposes(true), child: const Text('重试')),
    _purposeField(),
    const SizedBox(height: 12),
    _field(
      people,
      '参与人数',
      (s) => draft.people = s,
      keyboard: TextInputType.number,
      hint: _peopleFallback,
      invalid: (value) => (int.tryParse(value) ?? 0) <= 0 ? '请填写正整数' : null,
    ),
    const SizedBox(height: 12),
    _field(
      content,
      '活动内容',
      (s) => draft.content = s,
      lines: 3,
      hint: defaults?.activityContent,
    ),
    const SizedBox(height: 12),
    _field(
      joiners,
      '参与人说明',
      (s) => draft.joiners = s,
      lines: 2,
      hint: defaults?.joiners,
    ),
  ]);

  Widget _field(
    TextEditingController controller,
    String label,
    ValueChanged<String> changed, {
    TextInputType? keyboard,
    int lines = 1,
    String? hint,
    String? Function(String value)? invalid,
  }) {
    final fallback = hint?.trim() ?? '';
    final value = _value(controller, fallback);
    final message = !_submitted
        ? null
        : value.isEmpty
        ? '请填写$label'
        : invalid?.call(value);
    return TextField(
      controller: controller,
      onChanged: (s) {
        changed(s);
        if (_submitted) _refreshErrors();
      },
      keyboardType: keyboard,
      minLines: lines,
      maxLines: lines == 1 ? 1 : null,
      textInputAction: lines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        hintText: fallback.isEmpty ? null : fallback,
        // 有灰字默认值时标签常驻上方，避免与灰字重叠。
        floatingLabelBehavior: fallback.isEmpty
            ? null
            : FloatingLabelBehavior.always,
        errorText: message,
      ),
    );
  }

  Widget _purposeField() {
    final current = options.where((p) => p.key == draft.purpose).firstOrNull;
    final enabled = !loading && options.isNotEmpty;
    return InkWell(
      onTap: enabled ? _choosePurpose : null,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        isEmpty: current == null,
        isFocused: false,
        decoration: InputDecoration(
          labelText: '活动类型',
          errorText: _submitted && current == null ? '请选择活动类型' : null,
          enabled: enabled,
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: LoadingGlyph(),
                )
              : const Icon(Icons.expand_more),
        ),
        child: current == null
            ? null
            : Text(
                _purposeParts(current.name).$1,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      ),
    );
  }

  /// “学业支持类（串讲、答疑等）”拆为名称与示例，便于列表分行显示。
  static (String, String?) _purposeParts(String name) {
    final match = RegExp(r'^(.+?)[（(](.+)[）)]$').firstMatch(name.trim());
    return match == null ? (name, null) : (match[1]!, match[2]);
  }

  Future<void> _choosePurpose() async {
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                '活动类型',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final p in options)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(_purposeParts(p.name).$1),
                subtitle: switch (_purposeParts(p.name).$2) {
                  final example? => Text(example),
                  null => null,
                },
                selected: p.key == draft.purpose,
                trailing: p.key == draft.purpose
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(p.key),
              ),
          ],
        ),
      ),
    );
    if (!mounted || draft.generation != generation || value == null) return;
    _setPurpose(value);
  }
}
