import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'card_parts.dart' show BykcCardTags, BykcCardInfo, BykcCardFooter;
import 'display.dart'
    show uiBykcCheckinLabel, uiBykcPassLabel, uiBykcRange, uiBykcDate;

class BykcChosenCard extends StatelessWidget {
  const BykcChosenCard({
    required this.course,
    required this.onTap,
    this.action,
  });
  final BykcChosenPresentation course;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course.courseName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              BykcCardTags(
                category: course.subCategory,
                selfSign: (course.signPointCount ?? 0) > 0,
              ),
              BykcCardInfo(
                teacher: course.courseTeacher,
                position: course.coursePosition,
                time: uiBykcRange(course.courseStartDate, course.courseEndDate),
                deadlineLabel: '退选截止',
                // 退选截止已过时不再显示。
                deadline: switch (DateTime.tryParse(
                  course.courseCancelEndDate?.trim() ?? '',
                )) {
                  final end? when DateTime.now().isBefore(end) => uiBykcDate(
                    course.courseCancelEndDate!,
                  ),
                  _ => null,
                },
              ),
              BykcCardFooter(
                action: action,
                summary: Text(
                  [
                    uiBykcCheckinLabel(course.checkin),
                    uiBykcPassLabel(course.pass),
                    if (course.score != null) '${course.score} 分',
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: course.pass == 1 ? theme.colorScheme.primary : null,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
