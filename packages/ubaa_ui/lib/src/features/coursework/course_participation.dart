import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/write_callbacks.dart';
import '../../shared/dialogs/sheet.dart';
import '../../shared/text.dart' show uiHiddenAcademicField;
import '../../shared/when.dart' show uiCampusNow, uiShortRange;
import '../../theme.dart' show UbaaTheme;
import '../../common/tag.dart';
import 'signin_qr_sheet.dart' show showSigninQrSheet;
import 'signin_qr_button.dart';

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
    this.onFetchSigninQr,
    this.onSaveSigninQr,
    this.onCheckSigninStatus,
  });
  final FeatureId feature;
  final List<FeatureDetail> details;
  final Widget Function(FeatureDetail) evaluationRow;
  final SigninCourseQrFetcher? onFetchSigninQr;
  final SigninQrImageSaver? onSaveSigninQr;
  final SigninStatusChecker? onCheckSigninStatus;
  @override
  Widget build(BuildContext context) => feature == FeatureId.evaluation
      ? _EvaluationList(details: details, row: evaluationRow)
      : _SigninList(
          details: details,
          onFetchSigninQr: onFetchSigninQr,
          onSaveSigninQr: onSaveSigninQr,
          onCheckSigninStatus: onCheckSigninStatus,
        );
}

class _SigninList extends StatefulWidget {
  const _SigninList({
    required this.details,
    required this.onFetchSigninQr,
    required this.onSaveSigninQr,
    required this.onCheckSigninStatus,
  });
  final List<FeatureDetail> details;
  final SigninCourseQrFetcher? onFetchSigninQr;
  final SigninQrImageSaver? onSaveSigninQr;
  final SigninStatusChecker? onCheckSigninStatus;
  @override
  State<_SigninList> createState() => _SigninListState();
}

class _SigninListState extends State<_SigninList> {
  Timer? _tick;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tick?.cancel();
    _tick = null;
    if (!TickerMode.of(context)) return;
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
      return switch (signinPhase(p, now)) {
        SigninPhase.open => 0,
        SigninPhase.completed ||
        SigninPhase.completedOpen ||
        SigninPhase.unknown => 1,
        SigninPhase.upcoming => 2,
        SigninPhase.ended => 3,
      };
    }

    final ordered =
        [for (final (i, d) in widget.details.indexed) (i, d, rank(d))]
          ..sort((a, b) {
            final r = a.$3.compareTo(b.$3);
            return r != 0 ? r : a.$1.compareTo(b.$1);
          });
    return ListView.separated(
      padding: UbaaTheme.pageInsets(context, top: 8),
      itemCount: ordered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _SigninCourseCard(
        detail: ordered[index].$2,
        now: now,
        onFetchSigninQr: widget.onFetchSigninQr,
        onSaveSigninQr: widget.onSaveSigninQr,
        onCheckSigninStatus: widget.onCheckSigninStatus,
      ),
    );
  }
}

class _SigninCourseCard extends StatelessWidget {
  const _SigninCourseCard({
    required this.detail,
    required this.now,
    required this.onFetchSigninQr,
    required this.onSaveSigninQr,
    required this.onCheckSigninStatus,
  });
  final FeatureDetail detail;
  final DateTime now;
  final SigninCourseQrFetcher? onFetchSigninQr;
  final SigninQrImageSaver? onSaveSigninQr;
  final SigninStatusChecker? onCheckSigninStatus;

  @override
  Widget build(BuildContext context) {
    final p = detail.presentation! as SigninPresentation;
    final scheduleId = p.actionTarget?.trim() ?? '';
    final phase = signinPhase(p, now);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fetchQr = onFetchSigninQr;
    void openQr() {
      final currentPhase = signinPhase(p, uiCampusNow());
      if (fetchQr == null || !currentPhase.canOpenQr) return;
      final check = currentPhase.isCompleted ? null : onCheckSigninStatus;
      showSigninQrSheet(
        context,
        courseTitle: detail.title,
        fetch: (offset) => fetchQr(scheduleId, offset),
        save: onSaveSigninQr,
        closeWhenSigned: check == null ? null : () => check(scheduleId),
      );
    }

    final trailing = switch (phase) {
      SigninPhase.ended => const UiTag('未签到'),
      _ when phase.isCompleted || p.signStatus == 0 => SigninQrButton(
        phase: phase,
        onOpen: fetchQr == null ? null : openQr,
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
        borderRadius: BorderRadius.circular(UbaaTheme.cardRadius),
        side: BorderSide(
          color: phase == SigninPhase.open
              ? scheme.primary
              : scheme.outlineVariant,
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
                              fontWeight: FontWeight.w500,
                              color: phase == SigninPhase.ended
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
    final state = switch (p.signStatus) {
      0 => '未签到',
      1 => '已签到',
      _ => null,
    };
    return showUiSheet<void>(
      context,
      builder: (context) => UiSheetBody(
        title: detail.title,
        subtitle: state,
        children: [
          UiInfoRow(
            icon: Icons.schedule_outlined,
            text: uiShortRange(p.classBeginTime, p.classEndTime) ?? '时间未提供',
          ),
          for (final field in detail.fields)
            if (!uiHiddenAcademicField(field.label) &&
                field.value.trim().isNotEmpty)
              UiInfoRow(
                icon: Icons.info_outline,
                text: field.value,
                label: field.label,
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
      padding: UbaaTheme.pageInsets(context, top: 8),
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
