import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('旧调用无需新字段且preferredName规则不变', () {
    for (final name in <String?>[null, '', '   ']) {
      const account = 'fixture-account';
      final user = UserSummary(username: account, displayName: name);
      expect(user.preferredName, account);
      expect(user.schoolId, isNull);
      expect(user.email, isNull);
      expect(user.phone, isNull);
      expect(user.idCardTypeName, isNull);
    }
    expect(
      const UserSummary(
        username: 'fixture',
        displayName: ' 合成姓名 ',
      ).preferredName,
      ' 合成姓名 ',
    );
  });
}
