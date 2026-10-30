import 'package:ubaa_bindings/ubaa_bindings.dart';

Future<void>? _initialization;

/// 默认集合在同一进程内依次运行多个入口，FRB 只允许初始化一次。
Future<void> initializeRustLibrary() => _initialization ??= RustLib.init();
