import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

part 'write_coordinator/flow.dart';
part 'write_coordinator/invalidation.dart';
part 'write_coordinator/readback.dart';

final _now = DateTime.utc(2026, 9, 5, 9);

WriteIntent _intent({
  String id = 'intent-current',
  WriteOperation operation = WriteOperation.bykcSelectCourse,
  DateTime? expiresAt,
  FeatureQuery? readbackQuery,
}) => WriteIntent(
  intentId: id,
  operation: operation,
  targetSummary: '待确认操作',
  resolvedRoute: ConnectionMode.webvpn,
  warnings: const <String>[],
  expiresAt: expiresAt ?? _now.add(const Duration(minutes: 2)),
  requestDigest: 'safe-digest',
  readbackQuery: readbackQuery,
);

WriteCommitResult _result({
  WriteOperation operation = WriteOperation.bykcSelectCourse,
  bool success = true,
  bool unknown = false,
  CgyyReservationReceipt? receipt,
  EvaluationBatchResult? evaluationResult,
}) => WriteCommitResult(
  operation: operation,
  success: success,
  message: '已提交，请刷新核对',
  outcomeUnknown: unknown,
  resolvedRoute: ConnectionMode.webvpn,
  cgyyReceipt: receipt,
  evaluationResult: evaluationResult,
);

void main() {
  _registerFlowTests();
  _registerInvalidationTests();
  _registerReadbackTests();
}
