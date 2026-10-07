import 'dart:async';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_app/src/bridge/context.dart';
import '../assignments/reader.dart' show bridgeLoadAssignmentFeature;
import '../features/academic/reader.dart' show bridgeLoadAcademicFeature;
import '../features/bykc/reader.dart' show bridgeLoadBykcFeature;
import '../features/cgyy/reader.dart' show bridgeLoadCgyyFeature;
import '../features/evaluation/reader.dart' show bridgeLoadEvaluationFeature;
import '../features/libbook/reader.dart' show bridgeLoadLibbookFeature;
import '../features/ygdk/reader.dart' show bridgeLoadYgdkFeature;
import '../support/mapping.dart' show bridgeDateOnly, bridgeMapError;

Future<FeatureResult> bridgeLoadFeatureQuery(
  BridgeContext backend,
  FeatureId feature,
  FeatureQuery query, {
  bool loadYgdkRecords = true,
}) async {
  try {
    final today = bridgeDateOnly(query.date ?? DateTime.now());
    return await switch (feature) {
      FeatureId.schedule ||
      FeatureId.exam ||
      FeatureId.grades ||
      FeatureId.classroom => bridgeLoadAcademicFeature(
        backend,
        feature,
        query,
        today,
      ),
      FeatureId.spoc ||
      FeatureId.judge ||
      FeatureId.signin => bridgeLoadAssignmentFeature(backend, feature, query),
      FeatureId.bykc => bridgeLoadBykcFeature(backend, feature, query),
      FeatureId.libbook => bridgeLoadLibbookFeature(
        backend,
        feature,
        query,
        today,
      ),
      FeatureId.cgyy => bridgeLoadCgyyFeature(backend, feature, query, today),
      FeatureId.ygdk => bridgeLoadYgdkFeature(
        backend,
        feature,
        query,
        includeRecords: loadYgdkRecords,
      ),
      FeatureId.evaluation => bridgeLoadEvaluationFeature(
        backend,
        feature,
        query,
      ),
    };
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}
