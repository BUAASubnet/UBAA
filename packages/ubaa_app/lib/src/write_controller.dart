import 'write/coordinator.dart';

export 'write/coordinator.dart'
    show WriteCoordinator, WriteCommitter, WritePreparer, WriteDiscarder;
export 'write/receipt_verifier.dart' show WriteReceiptVerifier;

/// 兼容旧公共名字，继续使用唯一写入状态机及同一类型身份。
typedef WriteFlowController = WriteCoordinator;
