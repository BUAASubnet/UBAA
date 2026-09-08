import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';

void main() {
  test('提醒默认开启，重开存储后账号周次学期互不串用', () async {
    final dir = await Directory.systemTemp.createTemp(
      'ubaa-synthetic-reminders-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/reminders.json');
    final store = FileYgdkReminderStore(file);
    expect((await store.read('synthetic-a')).enabled, isTrue);
    await Future.wait([
      store.write(
        'synthetic-a',
        const YgdkReminderSettings(
          enabled: false,
          weekDoneKey: 'term:11',
          termDoneKey: 'term',
        ),
      ),
      store.write(
        'synthetic-b',
        const YgdkReminderSettings(weekDoneKey: 'term:12'),
      ),
    ]);
    final reopened = FileYgdkReminderStore(file);
    final a = await reopened.read('synthetic-a'),
        b = await reopened.read('synthetic-b');
    expect(a.enabled, isFalse);
    expect(a.weekDoneKey, 'term:11');
    expect(a.termDoneKey, 'term');
    expect(b.enabled, isTrue);
    expect(b.weekDoneKey, 'term:12');
    expect(b.termDoneKey, isNull);
    await reopened.clear('synthetic-a');
    expect((await reopened.read('synthetic-a')).enabled, isTrue);
    expect((await reopened.read('synthetic-b')).weekDoneKey, 'term:12');
  });
  test('损坏的提醒文件明确失败且不覆盖，空账号不能写入', () async {
    final dir = await Directory.systemTemp.createTemp(
      'ubaa-synthetic-reminders-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/reminders.json');
    await file.writeAsString('{invalid');
    final store = FileYgdkReminderStore(file);
    await expectLater(
      store.read('synthetic-a'),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.write('synthetic-a', const YgdkReminderSettings()),
      throwsA(isA<FormatException>()),
    );
    expect(await file.readAsString(), '{invalid');
    await expectLater(
      store.write('', const YgdkReminderSettings()),
      throwsArgumentError,
    );
  });
}
