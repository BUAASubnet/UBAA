import 'package:ubaa_domain/ubaa_domain.dart';

abstract interface class ScheduleImportBackend {
  Future<ScheduleImportTask> beginScheduleImport(String term);
}

abstract interface class ScheduleImportTask {
  Future<ScheduleImportProgress> next();
  void cancel();
}
