part of '../../widgets.dart';

Future<void> _showScheduleGroup(
  BuildContext context,
  List<FeatureDetail> details,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('同一时段的课程'),
    content: SizedBox(
      width: 560,
      height: MediaQuery.sizeOf(context).height * .6,
      child: ListView.builder(
        itemCount: details.length,
        itemBuilder: (context, index) {
          final detail = details[index];
          final p = detail.presentation! as ScheduleCoursePresentation;
          return ListTile(
            title: Text(detail.title),
            subtitle: Text(
              '第${p.beginSection}–${p.endSection}节 · ${_nonBlank(p.place) ?? '地点待公布'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showScheduleDetails(context, detail),
          );
        },
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

Future<void> _showScheduleDetails(BuildContext context, FeatureDetail detail) {
  final p = detail.presentation! as ScheduleCoursePresentation;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(detail.title),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * .65,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final field in <(String, String)>[
                ('课程代码', p.courseCode),
                if (p.courseSerialNo != null) ('课程序号', p.courseSerialNo!),
                if (p.credit != null) ('学分', p.credit!),
                ('上课地点', _nonBlank(p.place) ?? '地点待公布'),
                if (_timeRange(p.beginTime, p.endTime) case final time?)
                  ('上课时间', time),
                if (p.dayOfWeek case final day?)
                  ('星期', day >= 1 && day <= 7 ? _weekdays[day - 1] : '原值 $day'),
                if (p.beginSection case final start?) ('开始节次', '$start'),
                if (p.endSection case final end?) ('结束节次', '$end'),
                if (p.weeksAndTeachers != null) ('周次/教师', p.weeksAndTeachers!),
                if (p.teachingTarget != null) ('教学对象', p.teachingTarget!),
                for (final field in detail.fields) (field.label, field.value),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DetailField(label: field.$1, value: field.$2),
                ),
            ],
          ),
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
