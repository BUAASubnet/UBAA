import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import '../../recovery/startup_test.dart' as support;

void main() {
  Future<(AppController, _Backend, GradeScoreWatch)> setup() async {
    final backend = _Backend();
    final controller = AppController(backend: backend);
    await controller.initialize();
    await controller.refreshHome();
    backend.events.clear();
    final watch = GradeScoreWatch(
      controller: controller,
      store: MemoryGradeScoreStore(),
    );
    addTearDown(() {
      watch.dispose();
      controller.dispose();
    });
    return (controller, backend, watch);
  }

  test('自动成绩检查的学期读取让位今日课表且仍完整完成检查', () async {
    final (controller, backend, watch) = await setup();
    controller.setAppForeground(false);
    final home = controller.refreshHome(only: [FeatureId.schedule]);
    final checking = watch.check();
    controller.setAppForeground(true);
    await Future.wait([home, checking]);
    expect(backend.events, ['home.schedule', 'terms', 'grades.a']);
    expect(watch.error, isNull);
    expect(watch.checkedRoute, ConnectionMode.direct);
  });

  test('学期已知时自动成绩检查让位首页补充来源', () async {
    final (controller, backend, watch) = await setup();
    await controller.loadAcademicTerms();
    backend.events.clear();
    controller.setAppForeground(false);
    final checking = watch.check();
    await Future<void>.delayed(Duration.zero);
    final home = controller.loadHomeSupplement(HomeSupplement.bykcChosen);
    controller.setAppForeground(true);
    await Future.wait([checking, home]);
    expect(backend.events, ['home.bykcChosen', 'grades.a']);
    expect(watch.error, isNull);
  });

  test('用户打开学期选择器会提升自动检查已有请求且不重复读取', () async {
    final (controller, backend, watch) = await setup();
    controller.setAppForeground(false);
    final checking = watch.check();
    final home = controller.loadHomeSupplement(HomeSupplement.bykcChosen);
    final options = controller.loadAcademicTerms();
    controller.setAppForeground(true);
    await Future.wait([checking, home, options]);
    expect(backend.events, ['terms', 'home.bykcChosen', 'grades.a']);
  });

  test('用户同学期统计读取提升已排队自动检查且保留单次请求', () async {
    final (controller, backend, watch) = await setup();
    await controller.loadAcademicTerms();
    backend.events.clear();
    controller.setAppForeground(false);
    final checking = watch.check();
    await Future<void>.delayed(Duration.zero);
    final home = controller.loadHomeSupplement(HomeSupplement.bykcChosen);
    final explicit = controller.loadGradeTerm('a');
    controller.setAppForeground(true);
    await Future.wait([checking, home, explicit]);
    expect(backend.events, ['grades.a', 'home.bykcChosen']);
    expect((await explicit).overview, isA<GradesTermOverview>());
  });

  for (final started in [false, true]) {
    test('显式成绩视图合并自动检查，已发出=$started且按当前视图投影', () async {
      final (controller, backend, watch) = await setup();
      await controller.loadAcademicTerms();
      backend.events.clear();
      backend.gradeGate = Completer<FeatureResult>();
      controller.setAppForeground(started);
      final checking = watch.check();
      await Future<void>.delayed(Duration.zero);
      expect(backend.events, started ? ['grades.a'] : isEmpty);
      final explicit = controller.refreshFeatureQuery(
        FeatureId.grades,
        const FeatureQuery(term: 'a', view: FeatureQueryView.gradesMissing),
      );
      controller.setAppForeground(true);
      backend.gradeGate!.complete(_grades('a'));
      await Future.wait([checking, explicit]);
      expect(backend.events, ['grades.a']);
      final view = controller.snapshots[FeatureId.grades]!;
      expect(view.details.map((item) => item.title), ['合成待出']);
      expect((view.overview! as GradesTermOverview).grades, hasLength(2));
      expect(view.readContext?.query?.view, FeatureQueryView.gradesMissing);
    });
  }

  test('先打开成绩页再自动检查同一学期，仍只发送一次', () async {
    final (controller, backend, watch) = await setup();
    await controller.loadAcademicTerms();
    backend.events.clear();
    backend.gradeGate = Completer<FeatureResult>();
    final explicit = controller.refreshFeatureQuery(
      FeatureId.grades,
      const FeatureQuery(term: 'a'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(backend.events, ['grades.a']);
    final checking = watch.check();
    await Future<void>.delayed(Duration.zero);
    backend.gradeGate!.complete(_grades('a'));
    await Future.wait([explicit, checking]);
    expect(backend.events, ['grades.a']);
    expect(watch.checkedRoute, ConnectionMode.direct);
  });

  test('另一学期独立读取，同页面明确刷新仍产生新观察', () async {
    final (controller, backend, watch) = await setup();
    await controller.loadAcademicTerms();
    backend.events.clear();
    controller.setAppForeground(false);
    final checking = watch.check();
    const query = FeatureQuery(term: 'b');
    final explicit = controller.refreshFeatureQuery(FeatureId.grades, query);
    controller.setAppForeground(true);
    await Future.wait([checking, explicit]);
    expect(backend.events, ['grades.b', 'grades.a']);
    await controller.refreshFeatureQuery(FeatureId.grades, query);
    expect(backend.events, ['grades.b', 'grades.a', 'grades.b']);
    expect(
      (controller.snapshots[FeatureId.grades]!.overview! as GradesTermOverview)
          .requestTerm,
      'b',
    );
  });

  test('退出取消自动检查未发送的读取，不能复活提醒或学校调用', () async {
    final (controller, backend, watch) = await setup();
    await controller.loadAcademicTerms();
    backend.events.clear();
    controller.setAppForeground(false);
    final checking = watch.check();
    await Future<void>.delayed(Duration.zero);
    await controller.logout();
    controller.setAppForeground(true);
    await checking;
    expect(backend.events, isEmpty);
    expect(watch.notice, isNull);
    expect(watch.checkedRoute, isNull);
    expect(controller.phase, AppPhase.login);
  });
}

FeatureResult _grades(String term) => FeatureResult.success(
  overview: GradesTermOverview(
    requestTerm: term,
    termCode: term,
    grades: const [
      GradePresentation(courseCode: 'SAFE-1', courseName: '合成已出', score: '80'),
      GradePresentation(courseCode: 'SAFE-2', courseName: '合成待出'),
    ],
  ),
  resolvedRoute: ConnectionMode.direct,
);

class _Backend extends support.FakeRecoveryBackend
    implements FeatureQueryBackend, ProgressiveReadBackend {
  final events = <String>[];
  Completer<FeatureResult>? gradeGate;
  @override
  Future<FeatureReadTask?> beginFeatureRead(
    FeatureId feature,
    FeatureQuery? query,
  ) async => null;
  @override
  Future<FeatureResult> loadFeature(FeatureId feature) async {
    events.add('home.${feature.name}');
    return const FeatureResult.empty();
  }

  @override
  Future<FeatureResult> loadFeatureQuery(
    FeatureId feature,
    FeatureQuery query,
  ) async {
    if (query.view == FeatureQueryView.scheduleTerms) {
      events.add('terms');
      return const FeatureResult.success(
        details: [
          FeatureDetail(
            title: '合成学期',
            presentation: TermPresentation(code: 'a', selected: true, index: 0),
          ),
        ],
        resolvedRoute: ConnectionMode.direct,
      );
    }
    if (feature == FeatureId.grades) {
      events.add('grades.${query.term}');
      return gradeGate?.future ?? _grades(query.term!);
    }
    if (query.view == FeatureQueryView.bykcChosenCourses) {
      events.add('home.bykcChosen');
      return const FeatureResult.empty(resolvedRoute: ConnectionMode.direct);
    }
    throw StateError('未定义的脱敏读取');
  }
}
