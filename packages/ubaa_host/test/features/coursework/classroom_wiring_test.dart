import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_host/src/ubaa_app_host.dart' show SpocFilesDelivery;
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

  test('作业附件和课件下载清理暂存后仍向页面抛出 UiError', () async {
    final app = AppController(backend: _Backend());
    addTearDown(app.dispose);
    final saver = _Saver();
    final delivery = SpocFilesDelivery(
      service: app.spocFilesService!,
      saver: saver,
    );
    final expected = isA<UiError>()
        .having((error) => error.code, 'code', UbaaErrorCode.timeout)
        .having((error) => error.kind, 'kind', UbaaErrorKind.network);
    await expectLater(
      delivery.downloadAssignment(const SpocSubmittedFile(fileId: 'fixture')),
      throwsA(expected),
    );
    await expectLater(
      delivery.downloadCourse(
        const SpocCourseFile(
          id: 'fixture',
          name: '讲义',
          isFolder: false,
          downloadAllowed: true,
        ),
      ),
      throwsA(expected),
    );
    expect(saver.destinations, hasLength(2));
    for (final destination in saver.destinations) {
      expect(destination.discarded, isTrue);
      expect(destination.delivered, isFalse);
    }
  });
}

class _Saver implements BhpanFileSaver {
  final destinations = <_Destination>[];

  @override
  Future<BhpanDownloadDestination> select(
    String name,
    bool Function() isCurrent,
  ) async {
    final destination = _Destination();
    destinations.add(destination);
    return destination;
  }
}

class _Destination implements BhpanDownloadDestination {
  var discarded = false, delivered = false;

  @override
  String get path => 'fixture.pdf';
  @override
  bool get overwrite => false;
  @override
  Future<void> deliver(bool Function() isCurrent) async => delivered = true;
  @override
  Future<void> discard() async => discarded = true;
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

  static const _downloadFailure = BackendException(
    UbaaErrorCode.timeout,
    kind: UbaaErrorKind.network,
  );

  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadAssignmentFile(
    SpocSubmittedFile file,
    String destPath,
  ) async => throw _downloadFailure;

  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadCourseFile(
    SpocCourseFile file,
    String destPath,
  ) async => throw _downloadFailure;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
