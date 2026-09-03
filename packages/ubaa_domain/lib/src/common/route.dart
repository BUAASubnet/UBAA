/// 路由策略。Auto 由 Rust Core 根据可达性和会话状态解析。
enum RoutePolicy { auto, direct, webvpn }

extension RoutePolicyText on RoutePolicy {
  String get label => switch (this) {
    RoutePolicy.auto => '自动',
    RoutePolicy.direct => '直连',
    RoutePolicy.webvpn => 'WebVPN',
  };

  String get description => switch (this) {
    RoutePolicy.auto => '优先使用可用的校园网路线',
    RoutePolicy.direct => '直接连接校园服务',
    RoutePolicy.webvpn => '通过 WebVPN 连接校园服务',
  };

  String get wireName => switch (this) {
    RoutePolicy.auto => 'auto',
    RoutePolicy.direct => 'direct',
    RoutePolicy.webvpn => 'webvpn',
  };
}

/// 写入确认时显示的实际连接路线。
enum ConnectionMode { direct, webvpn }

extension ConnectionModeText on ConnectionMode {
  String get label => switch (this) {
    ConnectionMode.direct => '直连',
    ConnectionMode.webvpn => 'WebVPN',
  };
}
