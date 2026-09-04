import 'package:flutter/services.dart';

import 'media.dart';

/// 单次前台定位结果。
///
/// 构造时严格校验有限值和经纬度范围；字符串投影不包含坐标，避免定位数据
/// 被异常日志或调试输出意外记录。
final class PlatformLocation {
  factory PlatformLocation({required double lat, required double lng}) {
    if (!lat.isFinite || lat < -90 || lat > 90) {
      throw ArgumentError('纬度必须是 -90 到 90 之间的有限值');
    }
    if (!lng.isFinite || lng < -180 || lng > 180) {
      throw ArgumentError('经度必须是 -180 到 180 之间的有限值');
    }
    return PlatformLocation._(lat: lat, lng: lng);
  }

  const PlatformLocation._({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  String toString() => 'PlatformLocation(<已脱敏>)';
}

/// 获取单次前台位置的最小 typed 平台边界。
abstract interface class PlatformLocationProvider {
  bool get isAvailable;

  Future<PlatformLocation?> currentLocation();
}

/// 生产宿主使用的 MethodChannel 位置适配器。
///
/// 原生侧只返回 `lat`、`lng`；插件异常、畸形返回和越界坐标一律安全归约
/// 为空值，不向 Dart/UI 传播原始路径、令牌或异常正文。
final class MethodChannelLocationProvider implements PlatformLocationProvider {
  MethodChannelLocationProvider({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('cn.edu.buaa.ubaa/platform');

  final MethodChannel _channel;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  Future<bool> probe() async {
    try {
      _available =
          await _channel.invokeMethod<bool>('location.capability') ?? false;
    } on Object {
      _available = false;
    }
    return _available;
  }

  @override
  Future<PlatformLocation?> currentLocation() async {
    if (!_available) return null;
    try {
      final result = await _channel.invokeMethod<Object?>('location.current');
      if (result is! Map) return null;
      final lat = result['lat'];
      final lng = result['lng'];
      if (lat is! num || lng is! num) return null;
      return PlatformLocation(lat: lat.toDouble(), lng: lng.toDouble());
    } on Object {
      return null;
    }
  }
}

/// 没有原生定位实现时的安全默认值。
final class UnavailableLocationProvider implements PlatformLocationProvider {
  const UnavailableLocationProvider();

  @override
  bool get isAvailable => false;

  @override
  Future<PlatformLocation?> currentLocation() async => null;
}

/// 供 widget/integration 测试使用的确定性内存定位实现。
final class MemoryLocationProvider implements PlatformLocationProvider {
  MemoryLocationProvider({PlatformLocation? location, this.available = true})
    : _location = location;

  PlatformLocation? _location;
  final bool available;
  int requestCount = 0;

  @override
  bool get isAvailable => available;

  void setLocation(PlatformLocation? location) {
    _location = location;
  }

  @override
  Future<PlatformLocation?> currentLocation() async {
    requestCount++;
    return available ? _location : null;
  }
}

/// 在读取位置前强制申请前台定位权限的组合适配器。
final class PermissionedLocationProvider implements PlatformLocationProvider {
  PermissionedLocationProvider({
    required PlatformPermissionGateway permissions,
    required PlatformLocationProvider provider,
  }) : _permissions = permissions,
       _provider = provider;

  final PlatformPermissionGateway _permissions;
  final PlatformLocationProvider _provider;

  @override
  bool get isAvailable => _provider.isAvailable;

  @override
  Future<PlatformLocation?> currentLocation() async {
    if (!_provider.isAvailable) {
      throw const PlatformCapabilityException(
        PlatformPermission.foregroundLocation,
        PlatformPermissionStatus.unavailable,
      );
    }
    late final PlatformPermissionStatus status;
    try {
      status = await _permissions.request(
        PlatformPermission.foregroundLocation,
      );
    } on Object {
      throw const PlatformCapabilityException(
        PlatformPermission.foregroundLocation,
        PlatformPermissionStatus.unavailable,
      );
    }
    if (status != PlatformPermissionStatus.granted) {
      throw PlatformCapabilityException(
        PlatformPermission.foregroundLocation,
        status,
      );
    }
    try {
      final location = await _provider.currentLocation();
      if (location != null) return location;
    } on Object {
      // 原生定位错误只映射为稳定能力状态，不传播异常正文。
    }
    throw const PlatformCapabilityException(
      PlatformPermission.foregroundLocation,
      PlatformPermissionStatus.unavailable,
    );
  }
}
