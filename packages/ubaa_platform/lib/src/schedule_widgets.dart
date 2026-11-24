import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

abstract interface class ScheduleWidgetGateway {
  /// 原生端立即更换发布代次；换账号时同步撤销旧投影。
  Future<String> begin(String? owner);
  Future<void> publish(String scope, ScheduleWidgetSnapshot snapshot);
}

/// Android 与 iOS 原生组件共用的发布协议：同一 MethodChannel 上的
/// `begin`/`publish` 两个方法，快照 JSON 合同一致。
final class MethodChannelScheduleWidgetGateway
    implements ScheduleWidgetGateway {
  const MethodChannelScheduleWidgetGateway();
  static const _channel = MethodChannel('cn.edu.buaa.ubaa/schedule-widgets');
  @override
  Future<String> begin(String? owner) async {
    final value = await _channel.invokeMethod<String>('begin', {
      'owner': owner,
    });
    if (value == null || value.isEmpty)
      throw PlatformException(code: 'widget_unavailable');
    return value;
  }

  @override
  Future<void> publish(String scope, ScheduleWidgetSnapshot snapshot) =>
      _channel.invokeMethod<void>('publish', {
        'scope': scope,
        'snapshot': snapshot.toJson(),
      });
}

final class AndroidScheduleWidgetGateway
    extends MethodChannelScheduleWidgetGateway {
  const AndroidScheduleWidgetGateway();
}

final class IOSScheduleWidgetGateway
    extends MethodChannelScheduleWidgetGateway {
  const IOSScheduleWidgetGateway();
}
