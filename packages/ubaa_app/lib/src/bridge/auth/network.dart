import 'package:ubaa_bindings/ubaa_bindings.dart';
import '../../contracts/routing.dart';
import '../support/mapping.dart' show bridgeMapError;

final class BridgeNetworkOperation implements NetworkChangeOperation {
  BridgeNetworkOperation(this.handle);
  final BridgeNetworkChange handle;

  @override
  Future<BackendNetworkState> inspect() async {
    try {
      return switch (await handle.inspect()) {
        BridgeNetworkState.campus => BackendNetworkState.campus,
        BridgeNetworkState.offCampus => BackendNetworkState.offCampus,
        BridgeNetworkState.unknown => BackendNetworkState.unknown,
      };
    } on BridgeError catch (error) {
      throw bridgeMapError(error);
    }
  }

  @override
  void finish() => handle.finish();
  @override
  void cancel() => handle.cancel();
}
