import 'package:ubaa_domain/ubaa_domain.dart';

import '../../error_mapper.dart';

Future<T> _mapError<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on Object catch (error, stack) {
    Error.throwWithStackTrace(UbaaErrorMapper.fromObject(error), stack);
  }
}

final class UiClassroomService implements ClassroomService {
  const UiClassroomService(this._delegate);

  final ClassroomService _delegate;

  @override
  Future<ClassroomRead<ClassroomCatalog>> catalog(String kcid) =>
      _mapError(() => _delegate.catalog(kcid));

  @override
  Future<ClassroomRead<ClassroomSession>> session(
    String courseId,
    String subId,
  ) => _mapError(() => _delegate.session(courseId, subId));

  @override
  Future<ClassroomRead<ClassroomTranscript>> transcript(
    String subId,
    String resourceGuid,
  ) => _mapError(() => _delegate.transcript(subId, resourceGuid));

  @override
  Future<ClassroomRead<ClassroomSummary>> summary(
    String subId,
    String resourceGuid,
  ) => _mapError(() => _delegate.summary(subId, resourceGuid));

  @override
  Future<ClassroomRead<ClassroomSlides>> slides(
    String courseId,
    String subId,
    String resourceGuid,
  ) => _mapError(() => _delegate.slides(courseId, subId, resourceGuid));
}

final class UiSpocFilesService implements SpocFilesService {
  const UiSpocFilesService(this._delegate);

  final SpocFilesService _delegate;

  @override
  Future<SpocRead<List<SpocCourse>>> courses() => _mapError(_delegate.courses);

  @override
  Future<SpocRead<List<SpocCourseFile>>> courseFiles(
    String courseId, {
    String? folderId,
  }) => _mapError(() => _delegate.courseFiles(courseId, folderId: folderId));

  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadAssignmentFile(
    SpocSubmittedFile file,
    String destPath,
  ) => _mapError(() => _delegate.downloadAssignmentFile(file, destPath));

  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadCourseFile(
    SpocCourseFile file,
    String destPath,
  ) => _mapError(() => _delegate.downloadCourseFile(file, destPath));
}
