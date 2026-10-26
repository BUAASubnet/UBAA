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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                deadline: course.courseCancelEndDate == null
                    ? null
                    : uiBykcDate(course.courseCancelEndDate!),
              ),
              BykcCardFooter(
                action: action,
                summary: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      uiBykcCheckinLabel(course.checkin),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      uiBykcPassLabel(course.pass),
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (course.score != null)
                      Text(
                        '${course.score} 分',
                        style: theme.textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
