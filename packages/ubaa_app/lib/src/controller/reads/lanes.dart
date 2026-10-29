import 'package:ubaa_app/src/contracts/progressive.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../read_scheduler.dart';

ReadLane? controllerReadLane(Object backend, FeatureId feature) {
  if (backend is! ConcurrentReadBackend) return null;
  return switch (feature) {
    FeatureId.schedule ||
    FeatureId.exam ||
    FeatureId.grades ||
    FeatureId.classroom => ReadLane.academic,
    FeatureId.signin => ReadLane.signin,
    FeatureId.spoc => ReadLane.spoc,
    FeatureId.judge => ReadLane.judge,
    FeatureId.ygdk => ReadLane.ygdk,
    FeatureId.bykc => ReadLane.bykc,
    FeatureId.cgyy => ReadLane.cgyy,
    _ => null,
  };
}
