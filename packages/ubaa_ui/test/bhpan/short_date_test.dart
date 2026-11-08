import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_ui/src/features/bhpan/chrome.dart';

void main() {
  test('云盘列表短时间今年与往年使用同一中文日期写法', () {
    final now = DateTime.parse('2026-11-08T12:00:00+08:00');
    expect(
      bhpanShortDate(DateTime.parse('2026-11-08T09:05:00+08:00'), now: now),
      '今天 09:05',
    );
    expect(
      bhpanShortDate(DateTime.parse('2026-03-13T10:00:00+08:00'), now: now),
      '3月13日',
    );
    expect(
      bhpanShortDate(DateTime.parse('2025-12-08T10:00:00+08:00'), now: now),
      '2025年12月8日',
    );
  });
}
