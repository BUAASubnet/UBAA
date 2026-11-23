import 'package:ubaa_domain/ubaa_domain.dart';
import 'package:ubaa_platform/ubaa_platform.dart';
import 'package:ubaa_app/src/contracts/query.dart';
import '../state/state.dart' show ControllerState;

/// 续借后在 intent 原路线读取当前借阅，并只按原记录标识判断是否已更新。
///
/// 读取不重新解析 Auto 路线，不重发写请求。账号、会话或后端代次变化时
/// 返回 null，调用方保留结果未知；读取失败只记录诊断，不把未知升级为成功。
Future<LibraryLoanRenewReadback?> controllerVerifyLibraryLoanRenew(
  ControllerState controller,
  WriteIntent intent,
) async {
  final target = intent.libraryLoanRenewTarget;
  final backend = controller.internalBackend;
  if (target == null ||
      target.loanId.trim().isEmpty ||
      backend is! LibraryLoanReadbackBackend) {
    return null;
  }
  final scope = controller.internalCaptureSessionScope();
  if (!scope.isCurrent) return null;
  try {
    final read = await (backend as LibraryLoanReadbackBackend)
        .readLibraryLoansOnRoute(route: intent.resolvedRoute);
    if (!scope.isCurrent || read.resolvedRoute != intent.resolvedRoute) {
      return null;
    }
    final matches = read.loans
        .where((loan) => loan.id == target.loanId)
        .toList(growable: false);
    final after = matches.length == 1 ? matches.single : null;
    final beforeDate = _dueDate(target.dueDate);
    final afterDate = _dueDate(after?.dueDate);
    final dueDateExtended =
        beforeDate != null &&
        afterDate != null &&
        afterDate.isAfter(beforeDate);
    final renewCountIncreased =
        after?.renewTimes != null &&
        target.renewTimes != null &&
        after!.renewTimes! > target.renewTimes!;
    return LibraryLoanRenewReadback(
      loanId: target.loanId,
      loans: read.loans,
      route: read.resolvedRoute,
      status: dueDateExtended || renewCountIncreased
          ? LibraryRenewStatus.applied
          : beforeDate != null &&
                beforeDate == afterDate &&
                target.renewTimes != null &&
                target.renewTimes == after?.renewTimes
          ? LibraryRenewStatus.unchanged
          : LibraryRenewStatus.unknown,
    );
  } on Object catch (error, stackTrace) {
    if (scope.isCurrent) {
      controller.internalRecordFailure(
        error,
        DiagnosticOperation.readback,
        stackTrace: stackTrace,
        writeOperation: WriteOperation.libraryLoanRenew,
      );
    }
    return null;
  }
}

final _dateFormat = RegExp(
  r'^(\d{4})-(\d\d)-(\d\d)(?: (?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d)?$',
);

DateTime? _dueDate(String? text) {
  final match = text == null ? null : _dateFormat.firstMatch(text);
  if (match == null) return null;
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(int.parse(match[1]!), month, day);
  return date.month == month && date.day == day ? date : null;
}
