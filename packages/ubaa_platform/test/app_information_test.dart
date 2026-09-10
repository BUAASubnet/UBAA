import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('关于版本使用平台安装包信息，外链使用系统外部模式且不添加参数', () async {
    PackageInfo.setMockInitialValues(
      appName: '合成应用',
      packageName: 'synthetic',
      version: '3.2.1',
      buildNumber: '19',
      buildSignature: '',
    );
    final original = UrlLauncherPlatform.instance;
    final launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = original);
    final info = SystemAppInformation(isOhos: false);
    expect(await info.version(), '3.2.1+19');
    for (final link in AppLink.values) expect(await info.open(link), isTrue);
    expect(launcher.urls, [
      'https://github.com/BUAASubnet/UBAA',
      'https://github.com/BUAASubnet/UBAA/issues',
    ]);
    expect(
      launcher.modes,
      everyElement(PreferredLaunchMode.externalApplication),
    );
  });
  test('OHOS关于只传固定目的地名，平台失败返回明确不可用', () async {
    const channel = MethodChannel('synthetic/about');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'version') return '3.2.1+20';
          if (call.arguments == 'feedback')
            throw PlatformException(code: 'unavailable');
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final info = SystemAppInformation(isOhos: true, channel: channel);
    expect(await info.version(), '3.2.1+20');
    expect(await info.open(AppLink.project), isTrue);
    expect(await info.open(AppLink.feedback), isFalse);
    expect(calls.map((c) => c.method), ['version', 'openLink', 'openLink']);
    expect(calls.map((c) => c.arguments), [null, 'project', 'feedback']);
  });
}

class _Launcher extends UrlLauncherPlatform {
  @override
  get linkDelegate => null;
  final urls = <String>[];
  final modes = <PreferredLaunchMode>[];
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    modes.add(options.mode);
    return true;
  }
}
