part of '../widgets.dart';

extension _BykcPreferences on _UbaaMainShellState {
  Future<void> _loadBykcFilters() async {
    final load = widget.onLoadBykcFilters;
    if (load == null) return;
    final generation = _accountGeneration;
    final revision = _bykcFilterRevision;
    bool current() =>
        mounted &&
        generation == _accountGeneration &&
        revision == _bykcFilterRevision;
    try {
      final value = await load();
      if (current()) {
        _setBykcFilterState(value ?? const BykcCourseFilters.defaults(), null);
      }
    } on Object {
      if (current()) {
        _setBykcFilterState(
          const BykcCourseFilters.defaults(),
          '博雅筛选读取失败，已恢复默认选择。',
        );
      }
    }
  }

  Future<void> _saveBykcFilters(BykcCourseFilters value) async {
    final save = widget.onSaveBykcFilters;
    final generation = _accountGeneration;
    final revision = ++_bykcFilterRevision;
    // 选择立即生效；持久化失败也不能撤销用户正在使用的筛选。
    _setBykcFilterState(value, null);
    if (save == null) return;
    try {
      await save(value);
    } on Object {
      if (mounted &&
          generation == _accountGeneration &&
          revision == _bykcFilterRevision) {
        _setBykcFilterState(_bykcFilters, '筛选已生效，但未能保存，下次打开可能恢复原选择。');
      }
    }
  }
}
