import 'package:ubaa_domain/ubaa_domain.dart';

/// 已打开本机账号的独立核对提示通道，不授予写权限或重发提交。
abstract interface class WriteReadbackBackend {
  Future<List<WriteReadbackHint>> readWriteReadbackHints({
    required String accountId,
  });
  Future<void> dismissWriteReadbackHint(String id, {required String accountId});
}
