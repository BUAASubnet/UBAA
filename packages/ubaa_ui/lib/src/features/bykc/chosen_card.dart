part of '../../widgets.dart';

class _BykcChosenCard extends StatelessWidget {
  const _BykcChosenCard({required this.course, required this.onTap});
  final BykcChosenPresentation course;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              Text(
                course.courseName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              _BykcInfoLine('教师', course.courseTeacher, maxLines: 1),
              _BykcInfoLine('地点', course.coursePosition, maxLines: 1),
              _BykcInfoLine(
                '时间',
                _bykcRange(course.courseStartDate, course.courseEndDate),
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
                    _bykcCheckinLabel(course.checkin),
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    _bykcPassLabel(course.pass),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (course.score != null)
                    Text('${course.score} 分', style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
