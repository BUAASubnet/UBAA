import 'presentation.dart';

/// 仅包含本地课程筛选选择，不承载业务数据或动作资格。
final class BykcCourseFilters {
  factory BykcCourseFilters({
    Iterable<BykcCourseStatus> statuses = defaultStatuses,
    Iterable<String> categories = const [],
    Iterable<String> campuses = const [],
  }) {
    final normalizedCategories = _normalize(categories);
    final allowed = BykcCourseSubCategory.values
        .where((value) => value != BykcCourseSubCategory.unknown)
        .map((value) => value.displayName)
        .toSet();
    if (!allowed.containsAll(normalizedCategories)) {
      throw ArgumentError('博雅筛选类别无效');
    }
    return BykcCourseFilters._(
      Set.unmodifiable(statuses),
      normalizedCategories,
      _normalize(campuses),
    );
  }

  const BykcCourseFilters.defaults()
    : statuses = defaultStatuses,
      categories = const {},
      campuses = const {};

  const BykcCourseFilters._(this.statuses, this.categories, this.campuses);

  static const defaultStatuses = <BykcCourseStatus>{
    BykcCourseStatus.preview,
    BykcCourseStatus.available,
    BykcCourseStatus.full,
    BykcCourseStatus.selected,
  };

  /// 空集合明确表示不限；只有缺失整个偏好才使用默认四状态。
  final Set<BykcCourseStatus> statuses;
  final Set<String> categories, campuses;

  bool get isDefault => this == const BykcCourseFilters.defaults();

  BykcCourseFilters copyWith({
    Iterable<BykcCourseStatus>? statuses,
    Iterable<String>? categories,
    Iterable<String>? campuses,
  }) => BykcCourseFilters(
    statuses: statuses ?? this.statuses,
    categories: categories ?? this.categories,
    campuses: campuses ?? this.campuses,
  );

  static Set<String> _normalize(Iterable<String> values) => Set.unmodifiable(
    values.map((value) => value.trim()).where((value) => value.isNotEmpty),
  );

  @override
  bool operator ==(Object other) =>
      other is BykcCourseFilters &&
      _same(statuses, other.statuses) &&
      _same(categories, other.categories) &&
      _same(campuses, other.campuses);

  static bool _same<T>(Set<T> left, Set<T> right) =>
      left.length == right.length && left.containsAll(right);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(statuses),
    Object.hashAllUnordered(categories),
    Object.hashAllUnordered(campuses),
  );
}
