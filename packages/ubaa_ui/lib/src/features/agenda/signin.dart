part of 'view.dart';

extension AgendaSignin on AgendaViewState {
  DateTime get now {
    final value = widget.now ?? campusDate((widget.agendaClock ?? clock).now());
    return DateTime.utc(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  void _updateSigninTick() {
    if (widget.visible &&
        _tickerEnabled &&
        widget.now == null &&
        widget.onFetchSigninQr != null) {
      _signinTick ??= Timer.periodic(
        const Duration(minutes: 1),
        (_) => update(() {}),
      );
    } else {
      _signinTick?.cancel();
      _signinTick = null;
    }
  }

  SigninPresentation? _onlineSignin(
    AgendaNavigation navigation,
    DateTime current,
  ) {
    final date = homeDateKey(current);
    if (navigation.date != date) return null;
    return freshSigninDetail(
          widget.signinSnapshot,
          courseId: navigation.courseId,
          date: date,
        )?.presentation
        as SigninPresentation?;
  }

  Widget? _signinAction(AgendaEntry entry) {
    final school = entry.school;
    if (school == null || school.navigation.feature != AgendaFeature.signin)
      return null;
    final current = now;
    final course =
        _onlineSignin(school.navigation, current) ??
        SigninPresentation(
          courseId: school.navigation.courseId ?? '',
          classBeginTime:
              agendaStart(entry)?.toIso8601String().replaceFirst('Z', '') ?? '',
          classEndTime:
              agendaEnd(entry)?.toIso8601String().replaceFirst('Z', '') ?? '',
          signStatus: school.upstreamStatus.signStatus,
        );
    return switch (signinPhase(course, current)) {
      SigninPhase.ended => const UiTag('未签到'),
      final phase => SigninQrButton(
        phase: phase,
        onOpen: widget.onFetchSigninQr == null
            ? null
            : () => _openSigninQr(school),
      ),
    };
  }

  Future<void> _openSigninQr(SchoolAgendaItem school) async {
    final current = now;
    final course = _onlineSignin(school.navigation, current);
    final fetch = widget.onFetchSigninQr;
    if (!widget.visible || course == null || fetch == null) return;
    final phase = signinPhase(course, current);
    if (!phase.canOpenQr) return;
    final target = course.actionTarget!.trim();
    final check = phase.isCompleted ? null : widget.onCheckSigninStatus;
    await showSigninQrSheet(
      context,
      courseTitle: school.title,
      fetch: (offset) => fetch(target, offset),
      save: widget.onSaveSigninQr,
      closeWhenSigned: check == null ? null : () => check(target),
    );
  }
}
