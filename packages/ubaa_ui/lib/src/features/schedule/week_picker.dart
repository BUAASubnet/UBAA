import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../common/error_card.dart' show FriendlyErrorCard;
import '../../shared/dialogs/sheet.dart';
import '../../shared/loading.dart';

/// 保留原教学周顺序，重复编号全部待确认，不静默挑一个当权威值。
List<FeatureDetail> uiUniqueWeekOptions(FeatureResult result, String term) {
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

class AcademicWeekDialog extends StatefulWidget {
  const AcademicWeekDialog({
    required this.term,
    required this.selected,
    required this.loader,
  });
  final String term;
  final int? selected;
  final Future<FeatureResult> Function(bool) loader;
  @override
  State<AcademicWeekDialog> createState() => _AcademicWeekDialogState();
}

class _AcademicWeekDialogState extends State<AcademicWeekDialog> {
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

  /// 由 showUiSheet 打开的底部选择面板。
  @override
  Widget build(BuildContext context) => UiSheetBody(
    title: '选择教学周',
    actions: [
      OutlinedButton(onPressed: _reload, child: const Text('重新获取')),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
    ],
    children: [
      FutureBuilder<FeatureResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done)
            return const SizedBox(
              height: 64,
              child: Center(child: LoadingGlyph(dimension: 32)),
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
          final options = uiUniqueWeekOptions(snapshot.data!, widget.term);
          if (options.isEmpty) return const Text('暂无可确定的教学周，可取消后手动填写。');
          final colors = Theme.of(context).colorScheme;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final detail in options)
                if (detail.presentation case final WeekPresentation week)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(detail.title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${week.startDate}–${week.endDate}'),
                        if (week.current)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '本周',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: colors.onSecondaryContainer,
                                    ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    selected: week.number == widget.selected,
                    trailing: week.number == widget.selected
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(context).pop(week.number),
                  ),
            ],
          );
        },
      ),
    ],
  );
}
