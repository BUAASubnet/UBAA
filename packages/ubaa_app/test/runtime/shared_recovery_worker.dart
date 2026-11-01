import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ubaa_app/runtime.dart';
import 'shared_recovery_probe.dart' as probe;

Future<void> main(List<String> args) async {
  final root = Directory(args[0]);
  final input = StreamIterator(
    utf8.decoder.bind(stdin).transform(const LineSplitter()),
  );
  final release = Completer<void>();
  final backend = probe.FileBackend(
    root,
    loginGate: args[1] == 'hold' ? release.future : null,
    loginEntered: () => stdout.writeln('LOGIN'),
  );
  final accounts = await probe.openAccounts(root);
  final scope = await probe.capture(accounts);
  final service = probe.service(root, backend: backend);
  stdout.writeln('READY:$pid');
  await input.moveNext();
  final result = probe.ensure(service, scope);
  final observed = result.then(
    (_) => 'DONE',
    onError: (Object error) =>
        error is RecoveryInterrupted ? 'STOP' : 'ERROR:$error',
  );
  if (args[1] == 'hold') {
    await input.moveNext();
    release.complete();
  }
  stdout.writeln(await observed);
  await service.close();
  await input.cancel();
}
