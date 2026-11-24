import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../../../contracts/backend.dart';
import '../../support/mapping.dart' show bridgeMapError, bridgeToConnectionMode;

final class BridgeSpocFilesService implements SpocFilesService {
  const BridgeSpocFilesService(this.client);
  final BridgeClient client;

  Future<T> _read<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on BridgeError catch (error, stack) {
      Error.throwWithStackTrace(bridgeMapError(error), stack);
    }
  }

  @override
  Future<SpocRead<List<SpocCourse>>> courses() => _read(() async {
    final result = await client.spocCourses();
    return (
      route: bridgeToConnectionMode(result.route.resolvedRoute),
      data: [
        for (final item in result.data)
          SpocCourse(
            courseId: item.courseId,
            name: item.name,
            teacher: item.teacher,
          ),
      ],
    );
  });

  @override
  Future<SpocRead<List<SpocCourseFile>>> courseFiles(
    String courseId, {
    String? folderId,
  }) => _read(() async {
    final result = await client.spocCourseFiles(
      courseId: courseId,
      folderId: folderId,
    );
    return (
      route: bridgeToConnectionMode(result.route.resolvedRoute),
      data: [
        for (final item in result.data)
          SpocCourseFile(
            id: item.id,
            name: item.name,
            isFolder: item.isFolder,
            downloadAllowed: item.downloadAllowed,
            sizeText: item.sizeText,
            extension: item.extension_,
            uploadedAtText: item.uploadedAtText,
          ),
      ],
    );
  });

  SpocRead<SpocDownloadReceipt> _receipt(BridgeRoutedSpocDownload result) => (
    route: bridgeToConnectionMode(result.route.resolvedRoute),
    data: SpocDownloadReceipt(
      result.data.fileName,
      result.data.byteLen.toInt(),
    ),
  );

  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadAssignmentFile(
    SpocSubmittedFile file,
    String destPath,
  ) => _read(
    () async => _receipt(
      await client.spocDownloadAssignmentFile(
        fileId: file.fileId,
        fileName: file.fileName,
        destPath: destPath,
      ),
    ),
  );

  @override
  Future<SpocRead<SpocDownloadReceipt>> downloadCourseFile(
    SpocCourseFile file,
    String destPath,
  ) => _read(() async {
    if (file.isFolder || !file.downloadAllowed) {
      throw const BackendException(UbaaErrorCode.invalidInput);
    }
    return _receipt(
      await client.spocDownloadCourseFile(
        id: file.id,
        name: file.name,
        destPath: destPath,
      ),
    );
  });
}
