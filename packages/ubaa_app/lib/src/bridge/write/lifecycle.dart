part of 'operations.dart';

Future<void> bridgeDiscardWriteIntent(
  BridgeContext backend,
  String intentId,
) async {
  try {
    await backend.client.discardWriteIntent(intentId: intentId);
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}
