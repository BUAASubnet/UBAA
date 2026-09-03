import 'package:flutter_test/flutter_test.dart';
import 'package:ubaa_app/ubaa_app.dart';
import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';

part 'bridge_backend_characterization/auth.dart';
part 'bridge_backend_characterization/fakes.dart';
part 'bridge_backend_characterization/read.dart';
part 'bridge_backend_characterization/reduction.dart';
part 'bridge_backend_characterization/signatures.dart';
part 'bridge_backend_characterization/write_error.dart';

void main() {
  registerBridgeBackendSignatureCharacterization();
  registerBridgeBackendAuthCharacterization();
  registerBridgeBackendReadCharacterization();
  registerBridgeBackendReductionCharacterization();
  registerBridgeBackendWriteAndErrorCharacterization();
}
