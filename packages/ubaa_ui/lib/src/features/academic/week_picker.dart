part of '../../widgets.dart';

/// 保留原教学周顺序，重复编号全部待确认，不静默挑一个当权威值。
List<FeatureDetail> _uniqueWeekOptions(FeatureResult result, String term) {
  final candidates = result.details.where((detail) {
    final p = detail.presentation;
    return p is WeekPresentation && p.requestTerm == term && p.number > 0;
  }).toList();
  final counts = <int, int>{};
  for (final detail in candidates) {
    final n = (detail.presentation! as WeekPresentation).number;
    counts[n] = (counts[n] ?? 0) + 1;
  }
  return candidates
      .where((d) => counts[(d.presentation! as WeekPresentation).number] == 1)
      .toList();
}

extension _AcademicWeekControls on _FeatureQueryControlsState {
  Future<void> _chooseWeek() async {
    final loader = widget.onLoadAcademicWeeks;
    if (loader == null) return;
    if (_termController.text.trim().isEmpty) await _chooseTerm();
    if (!mounted || _termController.text.trim().isEmpty) return;
    final term = _termController.text.trim(), epoch = widget.readCacheEpoch;
    final selected = await showDialog<int>(
      context: context,
      builder: (_) => _AcademicWeekDialog(
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
      final options = _uniqueWeekOptions(result, term);
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

class _AcademicWeekDialog extends StatefulWidget {
  const _AcademicWeekDialog({
    required this.term,
    required this.selected,
    required this.loader,
  });
  final String term;
  final int? selected;
  final Future<FeatureResult> Function(bool) loader;
  @override
  State<_AcademicWeekDialog> createState() => _AcademicWeekDialogState();
}

class _AcademicWeekDialogState extends State<_AcademicWeekDialog> {
  late Future<FeatureResult> _future;
  @override
  void initState() {
    super.initState();
    _future = Future.sync(() => widget.loader(false));
  }

  void _reload() {
    final next = Future<FeatureResult>.sync(() => widget.loader(true));
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择教学周'),
    content: SizedBox(
      width: 480,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: SingleChildScrollView(
          child: FutureBuilder<FeatureResult>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done)
                return const SizedBox(
                  height: 64,
                  child: Center(child: CircularProgressIndicator()),
                );
              if (snapshot.data?.error case final error?)
                return FriendlyErrorCard(error: error, onRetry: _reload);
              if (snapshot.hasError || snapshot.data == null)
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('暂时无法获取教学周，可重试或手动填写。'),
                    TextButton(onPressed: _reload, child: const Text('重试')),
                  ],
                );
              final options = _uniqueWeekOptions(snapshot.data!, widget.term);
              if (options.isEmpty) return const Text('暂无可确定的教学周，可取消后手动填写。');
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final detail in options)
                    ListTile(
                      title: Text(detail.title),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(detail.presentation! as WeekPresentation).startDate}–${(detail.presentation! as WeekPresentation).endDate}',
                          ),
                          if ((detail.presentation! as WeekPresentation)
                              .current)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '本周',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSecondaryContainer,
                                      ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      selected:
                          (detail.presentation! as WeekPresentation).number ==
                          widget.selected,
                      trailing:
                          (detail.presentation! as WeekPresentation).number ==
                              widget.selected
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.of(
                        context,
                      ).pop((detail.presentation! as WeekPresentation).number),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _reload, child: const Text('重新获取')),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ],
  );
}
