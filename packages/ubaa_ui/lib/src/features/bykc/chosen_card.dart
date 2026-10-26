import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'display.dart'
    show BykcInfoLine, uiBykcCheckinLabel, uiBykcPassLabel, uiBykcRange;

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
          padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 4),
              BykcInfoLine('教师', course.courseTeacher, maxLines: 1),
              BykcInfoLine('地点', course.coursePosition, maxLines: 1),
              BykcInfoLine(
                '时间',
                uiBykcRange(course.courseStartDate, course.courseEndDate),
              ),
              if (course.subCategory != null ||
                  (course.signPointCount ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (course.subCategory != null)
                        Text(
                          course.subCategory!,
                          style: theme.textTheme.labelMedium,
                        ),
                      if ((course.signPointCount ?? 0) > 0)
                        Text('自主签到', style: theme.textTheme.labelMedium),
                    ],
                  ),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    uiBykcCheckinLabel(course.checkin),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    uiBykcPassLabel(course.pass),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (course.score != null)
                    Text('${course.score} 分', style: theme.textTheme.bodySmall),
                ],
              ),
              if (action != null) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
