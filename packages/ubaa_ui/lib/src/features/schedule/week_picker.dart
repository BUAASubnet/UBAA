import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../common/error_card.dart' show FriendlyErrorCard;
import '../../shared/dialogs/sheet.dart';
import '../../shared/loading.dart';
import '../../common/tag.dart';

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

/// 教学周起止日期：上游给「2026-09-07 00:00:00」，显示为「9月7日」；无法解析时原样显示。
String uiWeekDate(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(raw.trim());
  if (match == null) return raw;
  return '${int.parse(match[2]!)}月${int.parse(match[3]!)}日';
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
  final _targetKey = GlobalKey();
  bool _scrolled = false;
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
    // 重新获取是低频操作，放在标题右侧；底部面板下滑或点遮罩即可关闭，不再放「取消」。
    headerActions: [
      IconButton(
        tooltip: '重新获取',
        onPressed: _reload,
        icon: const Icon(Icons.refresh),
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
          if (options.isEmpty) return const Text('暂无可确定的教学周，可关闭后手动填写。');
          // 打开时滚到已选周（没有则本周），不用从第 1 周往下找。
          final target =
              options
                  .map((d) => d.presentation)
                  .whereType<WeekPresentation>()
                  .any((w) => w.number == widget.selected)
              ? widget.selected
              : options
                    .map((d) => d.presentation)
                    .whereType<WeekPresentation>()
                    .where((w) => w.current)
                    .firstOrNull
                    ?.number;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final context = _targetKey.currentContext;
            if (context != null && !_scrolled) {
              _scrolled = true;
              Scrollable.ensureVisible(context, alignment: .4);
            }
          });
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final detail in options)
                if (detail.presentation case final WeekPresentation week)
                  ListTile(
                    key: week.number == target ? _targetKey : null,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    // 大字或长周名时标签换到下一行，不挤压周名。
                    title: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          detail.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (week.current)
                          const UiTag('本周', tone: UiTagTone.primary),
                      ],
                    ),
                    subtitle: Text(
                      '${uiWeekDate(week.startDate)} – ${uiWeekDate(week.endDate)}',
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
