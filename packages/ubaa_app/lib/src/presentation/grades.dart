import 'package:ubaa_domain/ubaa_domain.dart';

/// 单次读取与已缓存学期使用同一白名单投影，不从兼容字段反解析成绩。
FeatureResult projectGrades(
  GradesTermOverview overview,
  FeatureQueryView view,
  ConnectionMode? route,
) {
  final grades = overview.grades
      .where(
        (item) => switch (view) {
          FeatureQueryView.gradesScored =>
            item.score?.trim().isNotEmpty ?? false,
          FeatureQueryView.gradesMissing =>
            !(item.score?.trim().isNotEmpty ?? false),
          _ => true,
        },
      )
      .toList(growable: false);
  final label = switch (view) {
    FeatureQueryView.gradesScored => '门已出成绩课程',
    FeatureQueryView.gradesMissing => '门待出成绩课程',
    _ => '门课程成绩',
  };
  return grades.isEmpty
      ? FeatureResult.empty(overview: overview, resolvedRoute: route)
      : FeatureResult.success(
          summary: '${grades.length}$label',
          overview: overview,
          resolvedRoute: route,
          details: List.unmodifiable(
            grades.map(
              (item) => FeatureDetail(
                title: item.courseName ?? item.courseCode ?? '课程',
                subtitle: item.courseCode,
                presentation: item,
                fields: List.unmodifiable([
                  for (final (label, value) in <(String, String?)>[
                    ('成绩', item.score),
                    ('绩点', item.gradePoint),
                    ('学分', item.credit?.toString()),
                    ('课程属性', item.courseType),
                  ])
                    if (value?.trim().isNotEmpty == true)
                      FeatureField(label: label, value: value!.trim()),
                ]),
              ),
            ),
          ),
        );
}
