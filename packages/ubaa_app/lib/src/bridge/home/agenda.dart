import 'package:ubaa_bindings/ubaa_bindings.dart';
import 'package:ubaa_domain/ubaa_domain.dart';
import '../agenda/school.dart';

/// 只复制兼容 DTO 的 typed 字段。筛选、时间解析、排序、紧迫判断全部交给 Core。
BridgeHomeAgendaInput bridgeHomeAgendaInputs(HomeTodoRequest request) {
  final bykc = <BridgeHomeBykc>[];
  final spoc = <BridgeHomeSpoc>[];
  final judge = <BridgeHomeJudge>[];
  final cgyy = <BridgeHomeCgyy>[];
  final signin = <BridgeHomeSignin>[];
  final exam = <BridgeHomeExam>[];
  final ygdk = <BridgeHomeYgdk>[];

  final date = homeDateKey(homeCampusTime(request.now));
  for (final snapshot in request.snapshots.values) {
    if (!homeAgendaSource(snapshot)) continue;
    final query = snapshot.readContext?.query;
    for (final detail in snapshot.details) {
      final p = detail.presentation;
      switch ((snapshot.feature, p)) {
        case (FeatureId.bykc, BykcChosenPresentation p):
          bykc.add(
            BridgeHomeBykc(
              courseId: p.courseId,
              title: p.courseName,
              teacher: p.courseTeacher,
              place: p.coursePosition,
              start: p.courseStartDate,
              end: p.courseEndDate,
              checkin: p.checkin,
              pass: p.pass,
            ),
          );
        case (FeatureId.spoc, SpocAssignmentPresentation p) when !p.isDetail:
          spoc.add(
            BridgeHomeSpoc(
              assignmentId: p.assignmentId,
              title: detail.title,
              courseName: p.courseName,
              teacher: p.teacherName,
              start: p.startTime,
              due: p.dueTime,
              status: _submission(p.status),
              statusText: p.statusText,
            ),
          );
        case (FeatureId.judge, JudgeAssignmentPresentation p) when !p.isDetail:
          judge.add(
            BridgeHomeJudge(
              courseId: p.courseId,
              assignmentId: p.assignmentId,
              title: detail.title,
              courseName: p.courseName,
              due: p.dueTime,
              status: _submission(p.status),
              statusText: p.statusText,
            ),
          );
        case (FeatureId.cgyy, CgyyOrderPresentation p):
          cgyy.add(
            BridgeHomeCgyy(
              orderId: p.id,
              venue: p.venueName,
              space: p.venueSpaceName,
              site: p.siteName,
              theme: p.theme,
              purpose: p.purposeTypeName,
              start: p.reservationStartDate,
              end: p.reservationEndDate,
              orderStatus: p.orderStatus,
              checkStatus: p.checkStatus,
            ),
          );
        case (FeatureId.signin, SigninPresentation p):
          signin.add(
            BridgeHomeSignin(
              fresh:
                  snapshot.status == FeatureLoadStatus.success &&
                  snapshot.evidence?.origin != DataOrigin.persisted &&
                  snapshot.evidence?.complete != false,
              date:
                  snapshot.evidence?.scopeDate ??
                  (snapshot.updatedAt == null
                      ? date
                      : homeDateKey(homeCampusTime(snapshot.updatedAt!))),
              courseId: p.courseId,
              title: detail.title,
              start: p.classBeginTime,
              end: p.classEndTime,
              signStatus: p.signStatus,
            ),
          );
        case (FeatureId.exam, ExamPresentation p) when p.arranged:
          exam.add(
            BridgeHomeExam(
              term: p.requestTerm ?? query?.term ?? '',
              title: detail.title,
              taskId: p.taskId,
              courseNo: p.courseNo,
              date: p.date,
              start: p.startTime,
              end: p.endTime,
              place: p.place,
              seat: p.seat,
              status: p.status,
            ),
          );
        default:
          break;
      }
    }
    final overview = snapshot.overview;
    if (snapshot.feature == FeatureId.ygdk &&
        (snapshot.evidence?.complete != false ||
            snapshot.evidence?.origin == DataOrigin.mixed) &&
        overview is YgdkOverview) {
      ygdk.add(
        BridgeHomeYgdk(
          weekCount: overview.weekCount,
          termCount: overview.termCount,
        ),
      );
    }
  }
  return BridgeHomeAgendaInput(
    bykc: bykc,
    spoc: spoc,
    judge: judge,
    cgyy: cgyy,
    signin: signin,
    exam: exam,
    ygdk: ygdk,
  );
}

bool homeAgendaSource(FeatureSnapshot snapshot) {
  if (snapshot.status != FeatureLoadStatus.success &&
      snapshot.status != FeatureLoadStatus.stale &&
      snapshot.status != FeatureLoadStatus.empty &&
      !(snapshot.status == FeatureLoadStatus.loading &&
          snapshot.updatedAt != null))
    return false;
  final query = snapshot.readContext?.query;
  return switch (snapshot.feature) {
    FeatureId.exam =>
      query == null ||
          query.view == FeatureQueryView.summary ||
          query.view == FeatureQueryView.examArranged,
    FeatureId.bykc => query?.view == FeatureQueryView.bykcChosenCourses,
    FeatureId.cgyy => query?.view == FeatureQueryView.cgyyOrders,
    FeatureId.spoc ||
    FeatureId.judge ||
    FeatureId.signin ||
    FeatureId.ygdk => query == null || query.view == FeatureQueryView.summary,
    _ => false,
  };
}

BridgeAgendaSubmission _submission(AssignmentSubmissionStatus s) =>
    BridgeAgendaSubmission.values.byName(s.name);
BridgeHomeAgendaContext bridgeHomeAgendaContext(HomeTodoRequest r) {
  final sunlightRoute = r.snapshots[FeatureId.ygdk]?.resolvedRoute;
  final w =
      r.currentWeekRoute != null &&
          sunlightRoute != null &&
          r.currentWeekRoute != sunlightRoute
      ? null
      : r.currentWeek;
  return BridgeHomeAgendaContext(
    now: BridgeAgendaTime(
      rfc3339:
          '${homeDateKey(homeCampusTime(r.now))}T${homeCampusTime(r.now).hour.toString().padLeft(2, '0')}:${homeCampusTime(r.now).minute.toString().padLeft(2, '0')}:${homeCampusTime(r.now).second.toString().padLeft(2, '0')}+08:00',
      timezone: 'Asia/Shanghai',
    ),
    currentWeek: w == null
        ? null
        : BridgeWeek(
            startDate: w.startDate,
            endDate: w.endDate,
            term: w.responseTerm,
            curWeek: w.current,
            serialNumber: w.number,
            name: '',
          ),
    ygdkEnabled: r.reminder.enabled,
    ygdkWeekDone:
        w != null && r.reminder.weekDoneKey == '${w.responseTerm}:${w.number}',
    ygdkTermDone: w != null && r.reminder.termDoneKey == w.responseTerm,
  );
}

HomeTodoProjection bridgeHomeTodoProjection(
  List<BridgeAgendaEntry> rows,
  HomeTodoRequest request, {
  AgendaFailure? overlayFailure,
}) {
  final now = homeCampusTime(request.now);
  final todos = <HomeTodo>[];
  for (final row in rows) {
    final school = row.school;
    final detail = school == null ? null : _freshSigninDetail(school, request);
    final signin = detail?.presentation as SigninPresentation?;
    if (school?.upstreamStatus.signStatus == 1 &&
        (signin == null ||
            signinPhase(signin, now) != SigninPhase.completedOpen)) {
      continue;
    }
    todos.add(
      formatHomeTodo(
        fromAgendaEntry(row),
        now: now,
        navigation: school == null
            ? null
            : agendaNavigation(fromAgendaNavigation(school.navigation)),
        signinAction: detail == null ? null : _signinAction(detail, signin!),
        signin: signin,
      ),
    );
  }
  return HomeTodoProjection(todos, overlayFailure: overlayFailure);
}

FeatureDetail? _freshSigninDetail(
  BridgeSchoolAgendaItem item,
  HomeTodoRequest request,
) {
  final date = homeDateKey(homeCampusTime(request.now));
  if (item.navigation.feature != BridgeAgendaFeature.signin ||
      item.navigation.date != date)
    return null;
  return freshSigninDetail(
    request.snapshots[FeatureId.signin],
    courseId: item.navigation.courseId,
    date: date,
  );
}

SigninPerformAction? _signinAction(
  FeatureDetail detail,
  SigninPresentation presentation,
) {
  final actions = detail.actions.whereType<SigninPerformAction>().toList();
  if (actions.length != 1 ||
      actions.single.eligibility != ActionEligibility.allowed ||
      actions.single.scheduleId != presentation.actionTarget ||
      actions.single.scheduleId.trim().isEmpty)
    return null;
  return actions.single;
}
