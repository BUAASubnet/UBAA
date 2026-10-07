part of 'query_controls.dart';

extension AcademicWeekControls on FeatureQueryControlsState {
  Future<void> _chooseWeek() async {
    final loader = widget.onLoadAcademicWeeks;
    if (loader == null) return;
    if (_termController.text.trim().isEmpty) await _chooseTerm();
    if (!mounted || _termController.text.trim().isEmpty) return;
    final term = _termController.text.trim(), epoch = widget.readCacheEpoch;
    final selected = await showDialog<int>(
      context: context,
      builder: (_) => AcademicWeekDialog(
        term: term,
        selected: int.tryParse(_weekController.text),
        loader: (force) => loader(term, force),
      ),
    );
    if (!mounted || selected == null) return;
    if (epoch != widget.readCacheEpoch || _termController.text.trim() != term) {
      _showMessage('学期或连接状态已变化，请重新选择教学周。');
      return;
    }
    _updateQueryDraft(() => _weekController.text = '$selected');
  }

  Future<void> _stepWeek(int delta) async {
    final loader = widget.onLoadAcademicWeeks;
    if (loader == null) return;
    final term = _termController.text.trim();
    final selected = int.tryParse(_weekController.text);
    if (term.isEmpty || selected == null) {
      await _chooseWeek();
      return;
    }
    final epoch = widget.readCacheEpoch;
    _updateQueryDraft(() => _submitting = true);
    try {
      final result = await loader(term, false);
      if (!mounted ||
          widget.readCacheEpoch != epoch ||
          _termController.text.trim() != term ||
          int.tryParse(_weekController.text) != selected)
        return;
      if (result.error case final error?) {
        _showMessage(error.message);
        return;
      }
      final options = uiUniqueWeekOptions(result, term);
      final index = options.indexWhere(
        (d) => (d.presentation! as WeekPresentation).number == selected,
      );
      if (index < 0) {
        _showMessage('当前周次不在返回列表中，请重新选择。');
        return;
      }
      final next = index + delta;
      if (next < 0 || next >= options.length) {
        _showMessage(delta < 0 ? '已到第一教学周' : '已到最后教学周');
        return;
      }
      _updateQueryDraft(
        () => _weekController.text =
            '${(options[next].presentation! as WeekPresentation).number}',
      );
    } on Object {
      if (mounted && widget.readCacheEpoch == epoch)
        _showMessage('暂时无法获取教学周，请重试。');
    } finally {
      if (mounted) _updateQueryDraft(() => _submitting = false);
    }
  }
}
