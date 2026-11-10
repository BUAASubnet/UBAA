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
    final info = SystemAppInformation();
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

  test('应用服务外链只允许 HTTPS，使用系统浏览器并保留原地址', () async {
    final original = UrlLauncherPlatform.instance;
    final launcher = _Launcher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = original);
    for (final value in [
      'http://example.invalid/update',
      'mailto:user@example.invalid',
      '/update',
      'https:relative',
    ]) {
      expect(await openExternalUrl(Uri.parse(value)), isFalse);
    }
    final safe = Uri.parse('https://example.invalid/update?version=2%2B10');
    expect(await openExternalUrl(safe), isTrue);
    expect(launcher.urls, [safe.toString()]);
    expect(launcher.modes, [PreferredLaunchMode.externalApplication]);
    launcher.result = false;
    expect(await openExternalUrl(safe), isFalse);
  });
}

class _Launcher extends UrlLauncherPlatform {
  @override
  get linkDelegate => null;
  final urls = <String>[];
  final modes = <PreferredLaunchMode>[];
  bool result = true;
  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    urls.add(url);
    modes.add(options.mode);
    return result;
  }
}
