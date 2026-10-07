import 'package:ubaa_domain/ubaa_domain.dart';

final fixtureNow = DateTime.utc(2026, 9, 5, 9);

WriteIntent fixtureIntent({
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
  expiresAt: expiresAt ?? fixtureNow.add(const Duration(minutes: 2)),
  requestDigest: 'safe-digest',
  readbackQuery: readbackQuery,
);

WriteCommitResult fixtureResult({
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
