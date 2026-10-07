import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/src/bridge/support/mapping.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('查询投影校验可独立执行，无效课程编号保持类型化错误', () {
    for (final value in <String?>[null, '', '0', '-1', 'abc']) {
      expect(
        () => bridgeRequiredPositiveQueryInt(value, '课程'),
        throwsA(
          isA<BackendException>().having(
            (error) => error.code,
            '错误码',
            UbaaErrorCode.invalidInput,
          ),
        ),
      );
    }
    expect(bridgeRequiredPositiveQueryInt(' 17 ', '课程'), 17);
  });
}
