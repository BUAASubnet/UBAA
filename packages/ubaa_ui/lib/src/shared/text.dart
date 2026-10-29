String? uiNonBlank(String? value) =>
    value == null || value.trim().isEmpty ? null : value;

String? uiTimeRange(String? start, String? end) {
  final first = uiNonBlank(start);
  final last = uiNonBlank(end);
  if (first != null && last != null) return '$first–$last';
  if (first != null) return '$first 开始';
  if (last != null) return '$last 结束';
  return null;
}

/// 课程号、课程代码、课序号、学期编码等教务内部编号，不向用户展示。
bool uiHiddenAcademicField(String label) {
  final key = label.replaceAll(RegExp(r'\s'), '').toLowerCase();
  return const {'课程号', '课程代码', '课程编号', '课程序号', '课序号', '课程id'}.contains(key);
}
