import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

import '../../support/controller/grades.dart';

const _attachment = SpocSubmittedFile(fileId: 'fixture');
const _courseFile = SpocCourseFile(
  id: 'fixture',
  name: '讲义',
  isFolder: false,
  downloadAllowed: true,
);

class _Backend extends FixtureGradesBackend
    implements
        ClassroomBackend,
        ClassroomService,
        SpocFilesBackend,
        SpocFilesService {
  late BackendException failure;

  @override
  ClassroomService get classroom => this;
  @override
  SpocFilesService get spocFiles => this;

  @override
  Future<ClassroomRead<ClassroomCatalog>> catalog(String kcid) async =>
      throw failure;
  @override
  Future<ClassroomRead<ClassroomSession>> session(
    String courseId,
    String subId,
  ) async => throw failure;
  @override
  Future<ClassroomRead<ClassroomTranscript>> transcript(
    String subId,
    String resourceGuid,
  ) async => throw failure;
  @override
  Future<ClassroomRead<ClassroomSummary>> summary(
    String subId,
    String resourceGuid,
  ) async => throw failure;
  @override
  Future<ClassroomRead<ClassroomSlides>> slides(
    String courseId,
    String subId,
    String resourceGuid,
  ) async => throw failure;

  @override
  Future<SpocRead<List<SpocCourse>>> courses() async => throw failure;
  @override
  Future<SpocRead<List<SpocCourseFile>>> courseFiles(
    String courseId, {
    String? folderId,
  }) async => throw failure;
  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadAssignmentFile(
    SpocSubmittedFile file,
    String destPath,
  ) async => throw failure;
  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadCourseFile(
    SpocCourseFile file,
    String destPath,
  ) async => throw failure;
}

void main() {
  late _Backend backend;
  late AppController app;
  setUp(() {
    backend = _Backend();
    app = AppController(backend: backend);
    addTearDown(app.dispose);
  });

  Matcher mappedError(UbaaErrorCode code, String reason, String message) {
    final diagnostic = ErrorDiagnostic.parse(
      '{"source":"crates/ubaa_core/src/features/spoc/classroom.rs:69",'
      '"stage":"spoc_mapping","reason":"$reason"}',
    )!;
    backend.failure = BackendException(
      code,
      detail: '不会传给界面的原文',
      kind: UbaaErrorKind.upstream,
      retryable: false,
      resolvedRoute: ConnectionMode.webvpn,
      issueId: 'fixture-issue',
      diagnostic: diagnostic,
    );
    return isA<UiError>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.kind, 'kind', UbaaErrorKind.upstream)
        .having((error) => error.diagnostic, 'diagnostic', same(diagnostic))
        .having((error) => error.retryable, 'retryable', false)
        .having(
          (error) => error.resolvedRoute,
          'resolvedRoute',
          ConnectionMode.webvpn,
        )
        .having((error) => error.issueId, 'issueId', 'fixture-issue')
        .having((error) => error.message, 'message', message);
  }

  final calls = <String, Future<Object> Function(AppController)>{
    'catalog': (app) => app.classroomService!.catalog('kcid'),
    'session': (app) => app.classroomService!.session('course', 'sub'),
    'transcript': (app) => app.classroomService!.transcript('sub', 'guid'),
    'summary': (app) => app.classroomService!.summary('sub', 'guid'),
    'slides': (app) => app.classroomService!.slides('course', 'sub', 'guid'),
    'courses': (app) => app.spocFilesService!.courses(),
    'courseFiles': (app) =>
        app.spocFilesService!.courseFiles('kcid', folderId: 'folder'),
    'downloadAssignmentFile': (app) => app.spocFilesService!
        .downloadAssignmentFile(_attachment, 'fixture.pdf'),
    'downloadCourseFile': (app) =>
        app.spocFilesService!.downloadCourseFile(_courseFile, 'fixture.pdf'),
  };
  for (final entry in calls.entries) {
    test('${entry.key} 向宿主抛出保留机器元数据的 UiError', () async {
      final expected = mappedError(
        UbaaErrorCode.businessUnavailable,
        'mapping_unbound_page',
        '该课程暂未在智学北航开通课堂',
      );
      await expectLater(entry.value(app), throwsA(expected));
    });
  }

  test('课堂目录保留教师身份诊断和专门文案', () async {
    final expected = mappedError(
      UbaaErrorCode.unsupported,
      'role_teacher_unsupported',
      '暂不支持教师身份',
    );
    await expectLater(app.classroomService!.catalog('kcid'), throwsA(expected));
  });
}
