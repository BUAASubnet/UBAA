part of 'view.dart';

extension _IhomeActions on _IhomeViewState {
  void _toggle(IhomeEntry entry) {
    if (_busy.contains(entry.appeal.id)) return;
    final key = _entryKey(entry);
    final opening = !_expanded.contains(key);
    _update(() {
      if (opening) {
        _expanded.add(key);
      } else {
        _expanded.remove(key);
      }
    });
    if (opening && !_details.containsKey(entry.appeal.id))
      unawaited(_readDetail(entry.appeal.id));
  }

  Future<void> _readDetail(int id) async {
    final service = widget.service;
    if (service == null || _detailLoading.contains(id) || _busy.contains(id))
      return;
    final revision = _revision, epoch = _epoch;
    _update(() {
      _detailLoading.add(id);
      _detailErrors.remove(id);
    });
    try {
      final value = await service.detail(id, mine: _scope == IhomeScope.mine);
      if (!mounted || epoch != _epoch || revision != _revision) return;
      _update(() {
        _details[id] = value;
        _uncertain.remove(id);
      });
    } on Object catch (error) {
      if (mounted && epoch == _epoch && revision == _revision)
        _update(
          () => _detailErrors[id] = error is UiError
              ? error.message
              : '详情读取失败，请重试',
        );
    } finally {
      if (mounted && epoch == _epoch && revision == _revision)
        _update(() => _detailLoading.remove(id));
    }
  }

  Future<void> _react(IhomeAppeal appeal, IhomeReaction reaction) async {
    final service = widget.service;
    final id = appeal.id;
    final current = reaction == IhomeReaction.follow
        ? appeal.isFollowed
        : appeal.isSupported;
    final route = _details[id]?.route ?? _route;
    if (service == null ||
        route == null ||
        current == null ||
        _loading ||
        _busy.contains(id) ||
        _uncertain.contains(id) ||
        _detailLoading.contains(id))
      return;
    final epoch = _epoch;
    final enabled = !current;
    final label = reaction == IhomeReaction.follow
        ? '关注'
        : _config?.supportLabel ?? '支持';
    _update(() => _busy.add(id));
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${enabled ? '' : '取消'}$label'),
          content: Text('确认${enabled ? '' : '取消'}$label这条诉求？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted || epoch != _epoch) return;
      _update(() {
        _detailErrors.remove(id);
        _submitting.add(id);
      });
      final result = await service.setReaction(id, reaction, enabled, route);
      if (mounted && epoch == _epoch) _update(() => _details[id] = result);
    } on Object catch (error) {
      if (mounted && epoch == _epoch)
        _update(() {
          _uncertain.add(id);
          _detailErrors[id] = error is UiError
              ? error.message
              : '操作结果未确认，请刷新后核对';
        });
    } finally {
      if (mounted && epoch == _epoch)
        _update(() {
          _busy.remove(id);
          _submitting.remove(id);
        });
    }
  }
}
