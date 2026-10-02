import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';

void main() {
  test('门锁专用材料不展开字符串或生成JSON，旧摘要保持原形状', () {
    const value = BridgeCgyyLockDisplay(
      code: 'synthetic-code',
      reservationReference: 'synthetic-reference',
      validForMillis: 30000,
    );
    expect('$value', isNot(contains('synthetic-code')));
    expect('$value', isNot(contains('synthetic-reference')));
    final sensitive = File(
      'lib/src/rust/api/sensitive.dart',
    ).readAsStringSync();
    expect(sensitive, isNot(contains('toJson')));
    expect(sensitive, isNot(contains('fromJson')));
    expect(sensitive, contains('void cancel();'));
    final normal = File('lib/src/rust/api/read.dart').readAsStringSync();
    final body = RegExp(
      r'class BridgeCgyyLockCode \{(.*?)\n\}',
      dotAll: true,
    ).firstMatch(normal)!.group(1)!;
    expect(body, contains('final bool available;'));
    expect(body, isNot(contains('String')));
    expect(normal, isNot(contains('reservationReference')));
  });
}
