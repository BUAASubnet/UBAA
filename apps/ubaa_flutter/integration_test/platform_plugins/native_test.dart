import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实插件私有目录与普通偏好写读重开删除', (tester) async {
    final directory = PrivateConfigDirectory(environment: {});
    await directory.initialize();
    expect(Directory(directory.resolve()).isAbsolute, isTrue);
    final scope =
        'ubaa-synthetic-plugin-${DateTime.now().microsecondsSinceEpoch}';
    PreferencesYgdkReminderStore reminders() =>
        PreferencesYgdkReminderStore(scope: scope);
    final filters = PreferencesBykcCourseFilterStore(scope: scope);
    addTearDown(() async {
      await reminders().clear('fixture');
      await filters.clearAccount('fixture');
    });
    await Future.wait([
      reminders().write(
        'fixture',
        const YgdkReminderSettings(enabled: false, weekDoneKey: 'fixture-week'),
      ),
      filters.write('fixture', BykcCourseFilters(categories: ['美育'])),
    ]);
    expect((await reminders().read('fixture')).enabled, isFalse);
    expect((await reminders().read('fixture')).weekDoneKey, 'fixture-week');
    expect(
      (await PreferencesBykcCourseFilterStore(
        scope: scope,
      ).read('fixture'))!.categories,
      {'美育'},
    );
    expect((await reminders().read('other-fixture')).enabled, isTrue);
    await reminders().clear('fixture');
    await filters.clearAccount('fixture');
    expect((await reminders().read('fixture')).weekDoneKey, isNull);
    expect(await filters.read('fixture'), isNull);
  });
}
