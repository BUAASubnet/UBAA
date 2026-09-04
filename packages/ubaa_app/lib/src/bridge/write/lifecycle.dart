part of '../bridge_backend.dart';

Future<void> _discardWriteIntent(BridgeBackend backend, String intentId) async {
  try {
    await backend.client.discardWriteIntent(intentId: intentId);
  } on BridgeError catch (error) {
    throw _mapError(error);
  }
}
