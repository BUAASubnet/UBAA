import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_ui/src/features/agenda/cache_status.dart';
import 'package:ubaa_ui/src/features/agenda/format.dart';

AgendaObservation _observation({
  required int verified,
  required int attempt,
  bool succeeded = true,
}) => AgendaObservation(
  scope: AgendaCacheScope(
    route: ConnectionMode.direct,
    kind: AgendaCacheKind.exams,
  ),
  fetchedAt: verified,
  lastVerifiedAt: verified,
  lastAttemptAt: attempt,
  lastAttemptSucceeded: succeeded,
  completeness: AgendaCompleteness.complete,
);

void main() {
  final now = DateTime.utc(2026, 11, 5, 15);
  final nowSeconds =
      DateTime.parse(agendaTime(now).rfc3339).millisecondsSinceEpoch ~/ 1000;
  final status = AgendaCacheStatus(sources: [], now: agendaTime(now));

  test('内容未变化的成功确认与取得新内容都显示为更新时间', () {
    final reused = _observation(
      verified: nowSeconds - 1800,
      attempt: nowSeconds - 60,
    );
    expect(status.freshness([reused]), '1 分钟前更新');
    final fresh = _observation(
      verified: nowSeconds - 120,
      attempt: nowSeconds - 120,
    );
    expect(status.freshness([fresh]), '2 分钟前更新');
  });

  test('失败的尝试不能当作更新完成', () {
    final failed = _observation(
      verified: nowSeconds - 1800,
      attempt: nowSeconds - 60,
      succeeded: false,
    );
    expect(status.freshness([failed]), '30 分钟前更新');
  });
}
