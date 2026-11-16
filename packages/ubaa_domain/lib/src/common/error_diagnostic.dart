import 'dart:convert';

/// Core 筛选后的诊断字段，与面向用户的提示分开保存。
final class ErrorDiagnostic {
  ErrorDiagnostic._(Map<String, Object?> fields)
    : _fields = Map.unmodifiable(fields);

  final Map<String, Object?> _fields;
  Map<String, Object?> toJson() => _fields;
  String? get reason => _fields['reason'] as String?;
  String? get upstreamMessage => _fields['upstream_message'] as String?;

  static ErrorDiagnostic? parse(String? text) {
    if (text == null || text.length > 2048) return null;
    try {
      final value = jsonDecode(text);
      if (value is! Map<String, dynamic>) return null;
      final fields = <String, Object?>{};
      for (final entry in value.entries) {
        final item = entry.value;
        final accepted = switch (entry.key) {
          'source' =>
            item is String &&
                item.length <= 200 &&
                RegExp(
                  r'^crates/ubaa_[a-z_]+/(?:src|tests)/[A-Za-z0-9_/]+\.rs:\d+$',
                ).hasMatch(item),
          'stage' || 'reason' =>
            item is String && RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(item),
          'json_types' =>
            item is Map &&
                item.entries.every(
                  (entry) =>
                      const {
                        'code',
                        'status',
                        'success',
                        'msg',
                        'message',
                        'errmsg',
                        'data',
                        'result',
                        'content',
                        'data.items',
                        'data.rows',
                        'data.list',
                        'result.items',
                        'content.list',
                      }.contains(entry.key) &&
                      const {
                        'null',
                        'boolean',
                        'number',
                        'string',
                        'array',
                        'object',
                      }.contains(entry.value),
                ),
          'upstream_code' =>
            item is int && item >= -2147483648 && item <= 2147483647,
          'status' => item is int && item >= 100 && item <= 599,
          'response_bytes' ||
          'json_line' ||
          'json_column' => item is int && item >= 0,
          'response_kind' => const {
            'json_object',
            'json_array',
            'json_null',
            'json_scalar',
            'login_html',
            'html',
            'text_or_binary',
          }.contains(item),
          'upstream_message' => const {
            '已报名过该课程，请不要重复报名',
            '报名失败，该课程人数已满',
            '选课失败，该课程不可选择',
            '您的会话已失效,请重新登录后再试',
          }.contains(item),
          _ => false,
        };
        if (!accepted) return null;
        fields[entry.key] = item;
      }
      return fields.containsKey('source') ? ErrorDiagnostic._(fields) : null;
    } on FormatException {
      return null;
    }
  }
}
