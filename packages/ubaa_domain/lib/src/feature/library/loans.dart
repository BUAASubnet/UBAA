import 'package:meta/meta.dart';

import '../../common/route.dart';

/// 图书馆对一条在借记录给出的业务状态；未识别的值保持为 unknown。
enum LibraryLoanStatus { normal, soon, overdue, other }

/// 一条当前借阅记录；标识只在当前账号与路线内作为续借目标。
@immutable
class LibraryLoan {
  const LibraryLoan({
    required this.id,
    required this.title,
    this.author,
    this.loanDate,
    this.dueDate,
    this.renewTimes,
    this.canRenewTimes,
    this.status = LibraryLoanStatus.other,
    this.location,
  });

  final String id;
  final String title;
  final String? author;
  final String? loanDate;
  final String? dueDate;
  final int? renewTimes;
  final int? canRenewTimes;
  final LibraryLoanStatus status;
  final String? location;
}

typedef LibraryLoansReader = Future<List<LibraryLoan>> Function();

/// 一次续借意图的只读核对基线，来自 Core 预检期间重新读取的记录。
@immutable
class LibraryLoanRenewTarget {
  const LibraryLoanRenewTarget({
    required this.loanId,
    this.dueDate,
    this.renewTimes,
  });

  final String loanId;
  final String? dueDate;
  final int? renewTimes;
}

enum LibraryRenewStatus { applied, unchanged, unknown }

/// 续借后在意图原路线读取的完整借阅范围及核对结论。
@immutable
class LibraryLoanRenewReadback {
  const LibraryLoanRenewReadback({
    required this.loanId,
    required this.loans,
    required this.route,
    required this.status,
  });

  final String loanId;
  final List<LibraryLoan> loans;
  final ConnectionMode route;

  /// 同一记录的应还日期延后，或续借次数增加时为 true。
  bool get verified => status == LibraryRenewStatus.applied;
  final LibraryRenewStatus status;
}
