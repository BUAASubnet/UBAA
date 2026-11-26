import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/ubaa_host.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_test_support/demo_backend.dart';
import 'package:ubaa_test_support/privacy.dart';
import 'package:ubaa_ui/ubaa_ui.dart';

void main() {
  testWidgets('宿主使用 SPOC 课程列表的精确标识打开课堂目录', (tester) async {
    final backend = _Backend();
    await tester.runAsync(
      () => backend.login(
        const LoginInput(username: 'fixture', password: 'fixture'),
      ),
    );
    Uri? opened;
    final playback = MemoryVideoPlaybackCapability();
    await tester.pumpWidget(
      UbaaAppHost(
        preferenceValues: acceptedPrivacyPreferences(),
        backend: backend,
        credentialVault: MemoryCredentialVault(),
        videoPlayback: playback,
        urlOpener: (uri) async {
          opened = uri;
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();

    final shell = tester.widget<UbaaMainShell>(find.byType(UbaaMainShell));
    final access = shell.spocClassroomAccess!;
    expect(backend.selectedCourseId, isNull);
    expect(access.playback, same(playback));
    final courses = (await access.courses()).data;
    expect(courses.first.name, courses.last.name);
    final catalog = await access.service.catalog(courses.last.courseId);
    expect(backend.selectedCourseId, 'fixture-002');
    expect(catalog.data.courseId, '102');
    final external = Uri.parse('https://example.invalid/video');
    await access.openExternal(external);
    expect(opened, external);
  });
}

class _Backend extends DemoBackend
    implements
        ClassroomBackend,
        ClassroomService,
        SpocFilesBackend,
        SpocFilesService {
  _Backend() : super(loginDelay: Duration.zero);

  String? selectedCourseId;

  @override
  ClassroomService get classroom => this;

  @override
  SpocFilesService get spocFiles => this;

  @override
  Future<SpocRead<List<SpocCourse>>> courses() async => (
    route: ConnectionMode.direct,
    data: const [
      SpocCourse(courseId: 'fixture-001', name: '同名课堂'),
      SpocCourse(courseId: 'fixture-002', name: '同名课堂'),
    ],
  );

  @override
  Future<ClassroomRead<ClassroomCatalog>> catalog(String kcid) async {
    selectedCourseId = kcid;
    return (
      route: ConnectionMode.direct,
      data: const ClassroomCatalog(
        courseId: '102',
        title: '同名课堂',
        teachers: [],
        termName: '合成学期',
        sessions: [],
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
