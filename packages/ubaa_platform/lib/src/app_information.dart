import 'package:flutter/foundation.dart';
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
  Future<bool> open(AppLink link) => openExternalUrl(Uri.parse(link.url));
}

/// 只把有效的 HTTPS 地址交给系统浏览器。
Future<bool> openExternalUrl(Uri url) async {
  if (!url.isScheme('https') || !url.hasAuthority || url.host.isEmpty)
    return false;
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

const _cashierBrowser = MethodChannel('cn.edu.buaa.ubaa/cashier-browser');

/// Android 使用应用自有浏览器；不支持应用内浏览时不退回外部浏览器。
Future<bool> supportsCampusCashier() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _cashierBrowser.invokeMethod<bool>('isSupported') ?? false;
    }
    return await supportsLaunchMode(LaunchMode.inAppWebView);
  } on Object {
    return false;
  }
}

final _cashierOrderId = RegExp(r'[A-Za-z0-9]{1,64}');

/// 在应用内打开航财通原订单；不注入会话或支付参数。
Future<bool> openCampusCashier(Uri url) async {
  if (!url.isScheme('https') ||
      url.host != 'cashier.cc-pay.cn' ||
      url.port != 443 ||
      url.userInfo.isNotEmpty ||
      url.path != '/cashier' ||
      url.hasFragment) {
    return false;
  }
  try {
    final query = url.queryParametersAll;
    final ids = query['id'];
    if (query.length != 1 || ids == null || ids.length != 1) return false;
    final id = ids.single;
    if (id.isEmpty || _cashierOrderId.stringMatch(id) != id) return false;
    if (!await supportsCampusCashier()) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _cashierBrowser.invokeMethod<bool>('open', url.toString()) ??
          false;
    }
    return await launchUrl(url, mode: LaunchMode.inAppWebView);
  } on Object {
    return false;
  }
}
