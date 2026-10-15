import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final read = File('lib/src/rust/api/read.dart').readAsStringSync();
  test('完整博雅 DTO 只暴露明确定义的显示字段', () {
    const fields = {
      'BridgeBykcCourseCatalogItem': [
        'BridgeBykcCourse course',
        'BridgeBykcCourseCategory? category',
        'BridgeBykcCourseSubCategory? subCategory',
        'List<String> audienceCampuses',
        'bool hasSignPoints',
      ],
      'BridgeBykcCourseCatalogPage': [
        'List<BridgeBykcCourseCatalogItem> content',
        'int totalElements',
        'int totalPages',
        'int size',
        'int number',
      ],
      'BridgeBykcCourseFullDetail': [
        'BridgeBykcCourseCatalogItem course',
        'String? courseContact',
        'String? courseContactMobile',
        'String? organizerCollegeName',
        'String? descriptionPlainText',
        'List<String> audienceColleges',
        'List<String> audienceTerms',
        'List<String> audienceGroups',
        'BridgeBykcSignDisplayConfig? signConfig',
        'BridgeBykcCourseAttendanceDisplay? attendance',
      ],
      'BridgeBykcSignDisplayConfig': [
        'String? signStartDate',
        'String? signEndDate',
        'String? signOutStartDate',
        'String? signOutEndDate',
        'int signPointCount',
      ],
      'BridgeBykcCourseAttendanceDisplay': [
        'PlatformInt64 recordId',
        'PlatformInt64 courseId',
        'int? checkin',
        'int? pass',
      ],
    };
    for (final entry in fields.entries) {
      final body = RegExp(
        'class ${entry.key} \\{(.*?)\\n\\}',
        dotAll: true,
      ).firstMatch(read)?.group(1);
      expect(body, isNotNull, reason: entry.key);
      final actual = RegExp(r'^\s*final\s+([^;{}]+);', multiLine: true)
          .allMatches(body!)
          .map((m) => m.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim())
          .toList();
      expect(actual, entry.value, reason: '${entry.key} 不能新增 raw、地址、坐标或写权限字段');
    }
  });
}
