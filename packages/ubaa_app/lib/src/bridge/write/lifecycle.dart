part of 'operations.dart';

Future<void> bridgeDiscardWriteIntent(
  BridgeContext backend,
  String intentId,
) async {
  try {
    if (intentId.startsWith('bhpan:')) {
      await backend.client.bhpanDiscard(handle: intentId.substring(6));
      return;
    }
    await backend.client.discardWriteIntent(intentId: intentId);
  } on BridgeError catch (error) {
    throw bridgeMapError(error);
  }
}
