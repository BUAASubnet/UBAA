import 'package:package_info_plus/package_info_plus.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:url_launcher/url_launcher.dart';

abstract interface class PlatformAppInformation {
  Future<String?> version();
  Future<bool> open(AppLink link);
}

/// 版本来自当前安装包；外链只交给系统浏览器，不经过学校会话。
final class SystemAppInformation implements PlatformAppInformation {
  @override
  Future<String?> version() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isEmpty) return null;
      return info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> open(AppLink link) async {
    try {
      return await launchUrl(
        Uri.parse(link.url),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      return false;
    }
  }
}
