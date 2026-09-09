import 'package:test/test.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

void main() {
  test('旧成绩变化规则首次及换学期不提醒，同分和仅删除不提醒', () {
    final first = baseline([grade('a', '80'), grade('b', '通过')]);
    expect(first.compareWith(null, ConnectionMode.direct), isNull);
    expect(first.compareWith(first, ConnectionMode.direct), isNull);
    expect(
      baseline([grade('a', '80')]).compareWith(first, ConnectionMode.direct),
      isNull,
    );
    expect(
      baseline([
        grade('a', '90'),
      ], term: 'other').compareWith(first, ConnectionMode.direct),
      isNull,
    );
  });
  test('成绩改变、新增已出和原分清空沿旧规则提醒，新增未出不提醒', () {
    final previous = baseline([grade('a', '80'), grade('b', '通过')]);
    final latest = baseline([
      grade('a', '90'),
      grade('b', ''),
      grade('c', '优秀'),
      grade('d', null),
    ]);
    final notice = latest.compareWith(previous, ConnectionMode.webvpn);
    expect(notice, isNotNull);
    expect(notice!.route, ConnectionMode.webvpn);
    expect(notice.changes.map((c) => (c.courseName, c.oldScore, c.newScore)), [
      ('合成a', '80', '90'),
      ('合成b', '通过', null),
      ('合成c', null, '优秀'),
    ]);
  });
  test('公开无ID时按课程号及名称后备，trim且无身份条目不进入基线', () {
    final previous = baseline([
      const GradePresentation(courseName: ' 合成名称 ', score: ' 80 '),
      const GradePresentation(score: '90'),
    ]);
    expect(previous.scores, hasLength(1));
    expect(previous.scores.single.key, 'name:合成名称');
    final latest = baseline([
      const GradePresentation(courseName: '合成名称', score: '90'),
    ]);
    expect(
      latest
          .compareWith(previous, ConnectionMode.direct)!
          .changes
          .single
          .oldScore,
      '80',
    );
  });
  test('课程号或名称有重复歧义时不将覆盖结果当成成绩变化', () {
    final unique = baseline([grade('same', '80')]);
    final duplicate = baseline([grade('same', '90'), grade('same', '70')]);
    expect(duplicate.compareWith(unique, ConnectionMode.direct), isNull);
    expect(unique.compareWith(duplicate, ConnectionMode.direct), isNull);
    expect(duplicate.scores, hasLength(2)); // 保留歧义，下一次不能冒充新增。
  });
}

GradePresentation grade(String code, String? score) =>
    GradePresentation(courseCode: code, courseName: '合成$code', score: score);
GradeScoreBaseline baseline(
  List<GradePresentation> grades, {
  String term = 'term',
}) => GradeScoreBaseline.fromRead(
  GradeTermRead(
    code: term,
    name: '合成学期',
    result: FeatureResult.success(
      overview: GradesTermOverview(
        requestTerm: term,
        termCode: term,
        grades: grades,
      ),
      resolvedRoute: ConnectionMode.direct,
    ),
  ),
);
