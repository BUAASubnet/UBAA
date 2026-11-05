import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/home/shell_helpers.dart';

void main() {
  const active = [ConnectionMode.direct, ConnectionMode.webvpn];
  test('自动路线从当前学校读取的缓存范围查询，双路线已登录时保留 WebVPN', () {
    expect(
      agendaRoute(RoutePolicy.auto, active, schoolRoute: ConnectionMode.webvpn),
      ConnectionMode.webvpn,
    );
  });
  test('固定路线继续使用明确策略，不被上次学校读取路线改变', () {
    expect(
      agendaRoute(
        RoutePolicy.direct,
        active,
        schoolRoute: ConnectionMode.webvpn,
      ),
      ConnectionMode.direct,
    );
    expect(
      agendaRoute(
        RoutePolicy.webvpn,
        active,
        schoolRoute: ConnectionMode.direct,
      ),
      ConnectionMode.webvpn,
    );
  });
}
