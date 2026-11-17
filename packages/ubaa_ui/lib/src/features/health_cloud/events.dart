import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

class HealthCloudEvents extends StatelessWidget {
  const HealthCloudEvents({
    super.key,
    required this.report,
    required this.viewportHeight,
  });
  final HealthCloudReport report;
  final double viewportHeight;

  HealthCloudEvent _event(List<String> names) {
    final matches = report.events.where((event) => names.contains(event.name));
    return matches.where((event) => event.result != null).firstOrNull ??
        matches.firstOrNull ??
        HealthCloudEvent(names.join(' / '));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final textHeight = MediaQuery.textScalerOf(context).scale(14);
      final gridWidth = math.min(constraints.maxWidth, 700.0);
      final gap = (gridWidth * .034).clamp(10.0, 20.0);
      final columns = gridWidth >= math.max(268, textHeight * 18) ? 2 : 1;
      final width = (gridWidth - gap * (columns - 1)) / columns;
      final height = ((viewportHeight - 20 - gap) / 2).clamp(104.0, 168.0);
      return Center(
        child: SizedBox(
          width: gridWidth,
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final names in const [
                ['1000米跑', '800米跑'],
                ['50米跑'],
                ['立定跳远'],
                ['引体向上', '仰卧起坐'],
              ])
                SizedBox(
                  width: width,
                  child: _EventCard(event: _event(names), minHeight: height),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.minHeight});
  final HealthCloudEvent event;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final status = event.status;
    final (background, foreground, label) = switch (status) {
      HealthCloudGrade.pass => (
        dark ? const Color(0xff146b53) : const Color(0xff00765a),
        Colors.white,
        '及格',
      ),
      HealthCloudGrade.fail => (
        dark ? const Color(0xffa63239) : const Color(0xffbd202d),
        Colors.white,
        '不及格',
      ),
      HealthCloudGrade.missing => (const Color(0xff6d7178), Colors.white, '缺项'),
      HealthCloudGrade.unknown => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        '未评分',
      ),
    };
    final points = event.score;
    final badge = switch ((status, points)) {
      (HealthCloudGrade.missing, _) => '缺',
      (_, null) => '—',
      (_, final double points) =>
        '${points == points.roundToDouble() ? points.toInt() : points}',
    };
    final rawResult = status == HealthCloudGrade.missing ? null : event.result;
    final result = switch ((event.name, rawResult)) {
      (_, null) => '—',
      ('50米跑', final String value) when value.endsWith('秒') =>
        '${value.substring(0, value.length - 1)}″',
      (_, final String value) => value.replaceFirst(RegExp(r'\s*厘米$'), ' cm'),
    };
    final badgeSize = (minHeight * .30).clamp(40.0, 50.0);
    const radius = BorderRadius.all(Radius.circular(11));
    return ClipRRect(
      borderRadius: radius,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: radius,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          14,
                          12,
                          8,
                          0,
                        ),
                        child: Text(
                          event.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Semantics(
                      label:
                          points == null || status == HealthCloudGrade.missing
                          ? label
                          : '$label，$badge 分',
                      excludeSemantics: true,
                      child: Container(
                        constraints: BoxConstraints(
                          minWidth: badgeSize,
                          minHeight: badgeSize,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: background,
                          borderRadius: const BorderRadiusDirectional.only(
                            bottomStart: Radius.circular(7),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Text(
                          badge,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: foreground,
                            fontSize: badgeSize * .40,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    14,
                    8,
                    10,
                    (minHeight * .17).clamp(12.0, 28.0),
                  ),
                  child: Text(
                    result,
                    semanticsLabel: event.name == '50米跑' ? rawResult : null,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: rawResult == null
                          ? colors.onSurfaceVariant
                          : colors.primary,
                      fontSize: (constraints.maxWidth * .134).clamp(24.0, 40.0),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
