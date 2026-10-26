import 'package:flutter/material.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'display.dart'
    show
        BykcInfoLine,
        BykcStatusChip,
        uiBykcDisplayStatus,
        uiBykcRange,
        uiBykcSelectTime;

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
          padding: const EdgeInsets.all(16),
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
                  const SizedBox(width: 8),
                  BykcStatusChip(uiBykcDisplayStatus(course)),
                ],
              ),
              const SizedBox(height: 4),
              BykcInfoLine('教师', course.courseTeacher, maxLines: 1),
              BykcInfoLine('地点', course.coursePosition, maxLines: 1),
              BykcInfoLine('类别', course.categoryDisplayName, maxLines: 1),
              BykcInfoLine(
                '适用校区',
                course.audienceCampuses.join('、'),
                maxLines: 1,
              ),
              if (course.hasSignPoints) const Text('设有签到地点'),
              BykcInfoLine(
                '时间',
                uiBykcRange(course.courseStartDate, course.courseEndDate),
              ),
              if (selectTime != null)
                BykcInfoLine(selectTime.label, selectTime.value),
              if (count != null || capacity != null) ...[
                const SizedBox(height: 12),
                if (count != null &&
                    count >= 0 &&
                    capacity != null &&
                    capacity > 0) ...[
                  LinearProgressIndicator(
                    value: (count / capacity).clamp(0, 1),
                    minHeight: 6,
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  count == null
                      ? '人数上限 $capacity'
                      : capacity == null
                      ? '已报名 $count'
                      : '已报名 $count / $capacity',
                  style: theme.textTheme.bodySmall,
                ),
              ],
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
