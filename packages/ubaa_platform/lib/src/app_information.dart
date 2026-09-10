import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:url_launcher/url_launcher.dart';

abstract interface class PlatformAppInformation {
  Future<String?> version();
  Future<bool> open(AppLink link);
}

/// 版本来自当前安装包；外链只交给系统浏览器，不经过学校会话。
final class SystemAppInformation implements PlatformAppInformation {
  SystemAppInformation({bool? isOhos, MethodChannel? channel})
    : _isOhos = isOhos ?? Platform.operatingSystem == 'ohos',
      _channel = channel ?? const MethodChannel('cn.edu.buaa.ubaa/about');
  final bool _isOhos;
  final MethodChannel _channel;

  @override
  Future<String?> version() async {
    try {
      if (_isOhos) return await _channel.invokeMethod<String>('version');
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
      if (_isOhos) {
        return await _channel.invokeMethod<bool>('openLink', link.name) ??
            false;
      }
      return await launchUrl(
        Uri.parse(link.url),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      return false;
    }
  }
}
