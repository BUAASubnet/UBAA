import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

WeekPresentation week(String start, String end) => WeekPresentation(
  requestTerm: 'term',
  responseTerm: 'term',
  number: 4,
  current: false,
  startDate: start,
  endDate: end,
);
List<String?> dates(WeekPresentation week) => week.headerDateLabels;
void main() {
  test('周日期沿旧版从真实开始日逐日显示而不依赖current标记', () {
    expect(dates(week('2026-04-13', '2026-04-19')), [
      '4-13',
      '4-14',
      '4-15',
      '4-16',
      '4-17',
      '4-18',
      '4-19',
    ]);
  });
  test('周日期跨年保持正确月日', () {
    expect(dates(week('2025-12-29', '2026-01-04')), [
      '12-29',
      '12-30',
      '12-31',
      '1-1',
      '1-2',
      '1-3',
      '1-4',
    ]);
  });
  test('无效开始日仅用真实结束日减六天，双无效不造日期', () {
    expect(dates(week('未知', '2026-04-19')).first, '4-13');
    expect(dates(week('未知', '待定')), List<String?>.filled(7, null));
  });
  test('周日期接受旧版不补零和日期时间格式但拒绝溢出日期', () {
    expect(
      dates(week('2026-4-13 00:00:00', '2026-4-19 23:59:59')).last,
      '4-19',
    );
    expect(dates(week('2026-02-30', '未知')), List<String?>.filled(7, null));
    expect(dates(week('2026-13-01', '未知')), List<String?>.filled(7, null));
  });
}
