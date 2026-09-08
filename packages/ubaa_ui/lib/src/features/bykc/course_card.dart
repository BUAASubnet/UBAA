part of '../../widgets.dart';

class _BykcCourseCard extends StatelessWidget {
  const _BykcCourseCard({required this.course, this.onTap});
  final BykcCoursePresentation course;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = course.courseCurrentCount, capacity = course.courseMaxCount;
    final selectTime = _bykcSelectTime(course);
    return Card(
      elevation: 2,
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
                  _BykcStatusChip(_bykcDisplayStatus(course)),
                ],
              ),
              const SizedBox(height: 4),
              _BykcInfoLine('教师', course.courseTeacher, maxLines: 1),
              _BykcInfoLine('地点', course.coursePosition, maxLines: 1),
              _BykcInfoLine(
                '时间',
                _bykcRange(course.courseStartDate, course.courseEndDate),
              ),
              if (selectTime != null)
                _BykcInfoLine(selectTime.label, selectTime.value),
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
            ],
          ),
        ),
      ),
    );
  }
}
