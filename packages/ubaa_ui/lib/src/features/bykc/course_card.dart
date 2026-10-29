import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'card_parts.dart' show BykcCardTags, BykcCardInfo, BykcCardFooter;
import 'display.dart'
    show BykcStatusChip, uiBykcDisplayStatus, uiBykcRange, uiBykcSelectTime;

class BykcCourseCard extends StatelessWidget {
  const BykcCourseCard({required this.course, this.onTap, this.action});
  final BykcCoursePresentation course;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = course.courseCurrentCount, capacity = course.courseMaxCount;
    final selectTime = uiBykcSelectTime(course);
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      course.courseName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // 可选、已满由选课按钮与人数进度表达，不再重复标签。
                  if (uiBykcDisplayStatus(course) case final status
                      when status != BykcCourseStatus.available &&
                          status != BykcCourseStatus.full) ...[
                    const SizedBox(width: 12),
                    BykcStatusChip(status),
                  ],
                ],
              ),
              BykcCardTags(
                category: course.categoryDisplayName,
                campuses: course.audienceCampuses,
                selfSign: course.hasSignPoints,
              ),
              BykcCardInfo(
                teacher: course.courseTeacher,
                position: course.coursePosition,
                time: uiBykcRange(course.courseStartDate, course.courseEndDate),
                deadlineLabel: selectTime?.label,
                deadline: selectTime?.value,
              ),
              if (count != null || capacity != null || action != null)
                BykcCardFooter(
                  action: action,
                  summary: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (count != null || capacity != null)
                            Text(
                              count == null
                                  ? '人数上限 $capacity'
                                  : capacity == null
                                  ? '已报名 $count'
                                  : '已报名 $count / $capacity',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          if (count != null &&
                              count >= 0 &&
                              capacity != null &&
                              capacity > 0) ...[
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: (count / capacity).clamp(0, 1),
                              minHeight: 5,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ],
                      ),
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
