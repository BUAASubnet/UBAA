part of 'form.dart';

extension YgdkFormDefaults on _YgdkFormPageState {
  FeatureDetail? get _defaultItem {
    final items = _validItems;
    for (final item in items) {
      if (_itemName(item).contains('跑')) return item;
    }
    int sort(FeatureDetail item) => item.presentation is YgdkItemPresentation
        ? (item.presentation as YgdkItemPresentation).sort ?? 2147483647
        : 2147483647;
    FeatureDetail? selected;
    for (final item in items) {
      if (selected == null || sort(item) < sort(selected)) selected = item;
    }
    return selected;
  }

  void _continue() {
    if (!_valid || _picking) return;
    final selected = _selected ?? (draft.itemKey == null ? _defaultItem : null);
    final photo =
        _photo ??
        YgdkPhotoInput(
          bytes: base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+lmCcAAAAASUVORK5CYII=',
          ),
          fileName: 'ygdk_auto.png',
          mimeType: 'image/png',
        );
    if (selected == null) {
      _showError('请选择可提交的运动项目。');
      return;
    }
    if (draft.start.trim().isEmpty != draft.end.trim().isEmpty) {
      _showError('开始时间和结束时间需要同时填写。');
      return;
    }
    var start = draft.start, end = draft.end;
    if (start.trim().isEmpty && end.trim().isEmpty) {
      final now = clock.now().toUtc().add(const Duration(hours: 8));
      final date = now.hour < 9 ? now.subtract(const Duration(days: 1)) : now;
      final hour = now.hour < 9 ? 20 : (now.hour - 1).clamp(8, 21);
      String format(int h) =>
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${h.toString().padLeft(2, '0')}:00';
      start = format(hour);
      end = format(hour + 1);
    }
    final input = YgdkSubmitInput(
      action: selected.action<YgdkSubmitAction>()!,
      startTime: start,
      endTime: end,
      place: draft.place.trim().isEmpty ? '操场' : draft.place.trim(),
      shareToSquare: draft.share,
      photo: photo,
    );
    _releasePhotoReferences();
    Navigator.of(context).pop(input);
  }
}
