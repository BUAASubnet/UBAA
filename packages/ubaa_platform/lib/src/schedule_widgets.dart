import 'package:flutter/services.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

abstract interface class ScheduleWidgetGateway {
  /// 原生端立即更换发布代次；换账号时同步撤销旧投影。
  Future<String> begin(String? owner);
  Future<void> publish(String scope, ScheduleWidgetSnapshot snapshot);
}

final class AndroidScheduleWidgetGateway implements ScheduleWidgetGateway {
  const AndroidScheduleWidgetGateway();
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
