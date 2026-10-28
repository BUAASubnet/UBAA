import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'support/preference_fake.dart';

void main() {
  const value = CgyyReservationDefaults(
    phone: 'synthetic-phone',
    theme: '合成主题',
    purposeType: 37,
    joinerNum: '3',
    activityContent: '合成讨论',
    joiners: '合成人员',
    isPhilosophySocialSciences: true,
    isOffSchoolJoiner: true,
  );
  for (final memory in [true, false]) {
    test('预约记忆读写并按账号隔离，明确清除保留其他账号：内存=$memory', () async {
      final values = FakePreferences();
      final CgyyReservationDefaultsStore store = memory
          ? MemoryCgyyReservationDefaultsStore()
          : PreferencesCgyyReservationDefaultsStore(
              scope: 'synthetic',
              values: values,
            );
      expect(await store.read('a'), isNull);
      await store.write('a', value);
      await store.write('b', value);
      final restored =
          await (memory
                  ? store
                  : PreferencesCgyyReservationDefaultsStore(
                      scope: 'synthetic',
                      values: values,
                    ))
              .read('a');
      expect(restored?.phone, value.phone);
      expect(restored?.theme, value.theme);
      expect(restored?.purposeType, 37);
      expect(restored?.joinerNum, '3');
      expect(restored?.activityContent, value.activityContent);
      expect(restored?.joiners, value.joiners);
      expect(restored?.isPhilosophySocialSciences, isTrue);
      expect(restored?.isOffSchoolJoiner, isTrue);
      await store.clearAccount('a');
      expect(await store.read('a'), isNull);
      expect((await store.read('b'))?.theme, value.theme);
    });
  }
  for (final raw in [
    '{',
    '{"purposeType":0}',
    '{"phone":3}',
    '{"philosophy":"yes"}',
  ]) {
    test('损坏预约记忆拒绝读写但允许明确清除：$raw', () async {
      final values = FakePreferences();
      final store = PreferencesCgyyReservationDefaultsStore(
        scope: 'synthetic',
        values: values,
      );
      await store.write('a', value);
      values.values[values.values.keys.single] = raw;
      await expectLater(
        store.read('a'),
        throwsA(isA<CgyyReservationDefaultsStoreException>()),
      );
      await expectLater(
        store.write('a', value),
        throwsA(isA<CgyyReservationDefaultsStoreException>()),
      );
      expect(values.values.values.single, raw);
      await store.clearAccount('a');
      await store.write('a', value);
      expect((await store.read('a'))?.purposeType, 37);
    });
  }
}
