import 'package:ubaa_ui/src/theme.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../../common/detail_fields.dart' show DetailField;
import '../../shared/text.dart' show uiHiddenAcademicField;
import '../../shared/when.dart'
    show uiCampusNow, uiClock, uiParseCampusTime, uiShortRange;
import '../../theme.dart' show UbaaTheme;

bool uiSupportsParticipationContent(
  FeatureId feature,
  List<FeatureDetail> details,
) => details.every(
  (detail) => switch (feature) {
    FeatureId.signin => detail.presentation is SigninPresentation,
    FeatureId.evaluation => detail.presentation is EvaluationCoursePresentation,
    _ => false,
  },
);

class CourseParticipationContent extends StatelessWidget {
  const CourseParticipationContent({
    required this.feature,
    required this.details,
    required this.evaluationRow,
    this.onSignin,
    this.writesEnabled = true,
  });
  final FeatureId feature;
  final List<FeatureDetail> details;
  final Widget Function(FeatureDetail) evaluationRow;
  final SigninStarter? onSignin;
  final bool writesEnabled;
  @override
  Widget build(BuildContext context) => feature == FeatureId.evaluation
      ? _EvaluationList(details: details, row: evaluationRow)
      : _SigninList(
          details: details,
          onSignin: onSignin,
          writesEnabled: writesEnabled,
        );
}

/// 课前 10 分钟到下课前可以签到；其余时间只显示状态。
const _signinLead = Duration(minutes: 10);

enum _SigninPhase { open, upcoming, ended, unknown }

({_SigninPhase phase, DateTime? opensAt}) _signinPhase(
  SigninPresentation p,
  DateTime now,
) {
  final begin = uiParseCampusTime(p.classBeginTime, day: now);
  final end = uiParseCampusTime(p.classEndTime, day: now);
  if (begin == null || end == null)
    return (phase: _SigninPhase.unknown, opensAt: null);
  final opens = begin.subtract(_signinLead);
  if (now.isBefore(opens))
    return (phase: _SigninPhase.upcoming, opensAt: opens);
  if (now.isBefore(end)) return (phase: _SigninPhase.open, opensAt: opens);
  return (phase: _SigninPhase.ended, opensAt: opens);
}

class _SigninList extends StatefulWidget {
  const _SigninList({
    required this.details,
    required this.onSignin,
    required this.writesEnabled,
  });
  final List<FeatureDetail> details;
  final SigninStarter? onSignin;
  final bool writesEnabled;
  @override
  State<_SigninList> createState() => _SigninListState();
}

class _SigninListState extends State<_SigninList> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // 签到窗口按分钟变化，定时刷新按钮与状态。
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = uiCampusNow();
    int rank(FeatureDetail d) {
      final p = d.presentation! as SigninPresentation;
      return switch (_signinPhase(p, now).phase) {
        _SigninPhase.open => p.signStatus == 1 ? 1 : 0,
        _SigninPhase.unknown => 1,
        _SigninPhase.upcoming => 2,
        _SigninPhase.ended => 3,
      };
    }

    final ordered = [for (final (i, d) in widget.details.indexed) (i, d)]
      ..sort((a, b) {
        final r = rank(a.$2).compareTo(rank(b.$2));
        return r != 0 ? r : a.$1.compareTo(b.$1);
      });
    return ListView.separated(
      padding: UbaaTheme.pageInsets(context),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _SigninCourseCard(
        detail: ordered[index].$2,
        now: now,
        onSignin: widget.onSignin,
        writesEnabled: widget.writesEnabled,
      ),
    );
  }
}

class _SigninCourseCard extends StatelessWidget {
  const _SigninCourseCard({
    required this.detail,
    required this.now,
    required this.onSignin,
    required this.writesEnabled,
  });
  final FeatureDetail detail;
  final DateTime now;
  final SigninStarter? onSignin;
  final bool writesEnabled;

  @override
  Widget build(BuildContext context) {
    final p = detail.presentation! as SigninPresentation;
    final action = detail.action<SigninPerformAction>();
    final done = p.signStatus == 1;
    final allowed =
        action?.eligibility == ActionEligibility.allowed &&
        action!.scheduleId.trim().isNotEmpty;
    final window = _signinPhase(p, now);
    final canSignNow = !done && window.phase == _SigninPhase.open;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget tag(String text, Color fg, Color bg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
    final Widget? trailing = done
        ? tag('已签到', scheme.onPrimaryContainer, scheme.primaryContainer)
        : canSignNow && onSignin != null && action != null
        ? FilledButton(
            onPressed: writesEnabled && allowed
                ? () => onSignin!(action)
                : null,
            child: const Text('签到'),
          )
        : switch (window.phase) {
            _SigninPhase.upcoming => tag(
              '${uiClock(window.opensAt!)} 起可签',
              scheme.onSurfaceVariant,
              scheme.surfaceContainerHighest,
            ),
            _SigninPhase.ended => tag(
              '未签到',
              scheme.onSurfaceVariant,
              scheme.surfaceContainerHighest,
            ),
            _ => null,
          };
    final time =
        uiShortRange(
          p.classBeginTime,
          p.classEndTime,
          withDate: false,
          now: now,
        ) ??
        '时间未提供';
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: canSignNow && !done ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Tooltip(
        message: '课程详情',
        child: InkWell(
          onTap: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: window.phase == _SigninPhase.ended && !done
                                  ? scheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            time,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 12),
                      trailing,
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDetails(BuildContext context) {
    final p = detail.presentation! as SigninPresentation;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(detail.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(uiShortRange(p.classBeginTime, p.classEndTime) ?? '时间未提供'),
              if (switch (p.signStatus) {
                    0 => '未签到',
                    1 => '已签到',
                    _ => null,
                  }
                  case final state?)
                Text(state),
              const SizedBox(height: 12),
              for (final field in detail.fields.where(
                (f) => !uiHiddenAcademicField(f.label),
              ))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DetailField(label: field.label, value: field.value),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

/// 待评在前；已评默认收起，减少需要滚动的内容。
class _EvaluationList extends StatelessWidget {
  const _EvaluationList({required this.details, required this.row});
  final List<FeatureDetail> details;
  final Widget Function(FeatureDetail) row;
  bool _done(FeatureDetail d) =>
      (d.presentation! as EvaluationCoursePresentation).isEvaluated;
  @override
  Widget build(BuildContext context) {
    final pending = details.where((d) => !_done(d)).toList();
    final done = details.where(_done).toList();
    return ListView(
      padding: UbaaTheme.pageInsets(context),
      children: [
        for (final detail in pending) row(detail),
        if (done.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const PageStorageKey('evaluation-done'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              initiallyExpanded: pending.isEmpty,
              title: Text('已评 ${done.length} 门'),
              children: [for (final detail in done) row(detail)],
            ),
          ),
      ],
    );
  }
}
