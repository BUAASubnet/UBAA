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
