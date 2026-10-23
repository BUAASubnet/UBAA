part of '../shell.dart';

extension RecentFeatures on _UbaaMainShellState {
  Future<void> _loadRecentFeatures() async {
    final load = widget.onLoadRecentFeatures;
    if (load == null) return;
    final generation = _accountGeneration;
    final revision = _recentRevision;
    try {
      final saved = await load();
      if (!mounted ||
          generation != _accountGeneration ||
          revision != _recentRevision)
        return;
      final visitedWhileLoading = _recentFeatures.isNotEmpty;
      _setRecentFeatures({..._recentFeatures, ...saved}.take(4).toList());
      if (visitedWhileLoading) {
        await widget.onSaveRecentFeatures?.call(
          List.unmodifiable(_recentFeatures),
        );
      }
    } on Object {
      // 普通入口排序读取失败时继续使用本轮访问记录，不阻断导航。
    }
  }

  void _recordFeatureVisit(FeatureId feature) {
    _setRecentFeatures({feature, ..._recentFeatures}.take(4).toList());
    final save = widget.onSaveRecentFeatures;
    if (save != null) {
      unawaited(_saveRecentFeatures(save, List.unmodifiable(_recentFeatures)));
    }
  }

  Future<void> _saveRecentFeatures(
    Future<void> Function(List<FeatureId>) save,
    List<FeatureId> value,
  ) async {
    try {
      await save(value);
    } on Object {
      // 保存失败保留本轮排序，下次访问仍会尝试保存。
    }
  }
}
