import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实网络插件通道可读取、订阅及重新订阅', (tester) async {
    // 不创建学校客户端、不改变系统网络；none 也是合法的离线结果。
    final connectivity = Connectivity();
    final state = await connectivity.checkConnectivity().timeout(
      const Duration(seconds: 10),
    );
    expect(state, isNotEmpty);
    expect(state, everyElement(isA<ConnectivityResult>()));
    // first 完成后取消订阅；再次订阅验证原生handler可重新建立。
    // 插件应发送当前状态，缺注册/通道异常/超时均直接令测试失败。
    for (var round = 0; round < 2; round++) {
      final event = await connectivity.onConnectivityChanged.first.timeout(
        const Duration(seconds: 10),
      );
      expect(event, isNotEmpty);
      expect(event, everyElement(isA<ConnectivityResult>()));
    }
  });
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
