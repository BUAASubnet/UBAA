part of 'shell.dart';

extension _ShellCourseHub on _UbaaMainShellState {
  /// 课程主页的标题用课程名；找不到课程时退回页面名。
  String? get _hubTitle =>
      _hubPage?.pageTitle(widget.courseHub?.value, _courseKey);

  void _openHub(CourseHubPage page, [String? key]) {
    if (_writeBusy || widget.courseHub == null) return;
    final snapshot = widget.courseHub!.value;
    if (key != null && !snapshot.courses.any((item) => item.key == key)) return;
    _selectTab(UiDestination.study.index);
    _changeNavigation(() {
      _hubPage = page;
      _courseKey = key;
      _courseTerm = snapshot.termCode;
    });
  }

  Widget _buildStudyRoot() {
    final grid = FeatureGridView(
      features: UiDestination.study.features,
      homeState: widget.homeState,
      snapshots: widget.snapshots,
      onFeatureTap: _openFeatureList,
      onRetryFeature: widget.onRetryFeature,
    );
    return buildStudyRoot(
      grid: grid,
      courseHub: widget.courseHub,
      onOpenFeature: _openFeatureList,
      onRefresh: widget.onRefreshCourseHub,
      onCourse: (key) => _openHub(CourseHubPage.course, key),
      onAssignments: () => _openHub(CourseHubPage.assignments),
      onSources: () => _openHub(CourseHubPage.sources),
    );
  }

  Widget _buildHubPage() => ValueListenableBuilder(
    valueListenable: widget.courseHub!,
    builder: (_, snapshot, _) => _hubPage!.build(
      snapshot,
      courseKey: _courseKey,
      term: _courseTerm,
      onOpenAssignment: _openHomeNavigation,
      onOpenFeature: _openFeatureList,
      onRefresh: widget.onRefreshCourseHub,
      onSetJudgeLink: widget.onSetJudgeLink,
      classroomAccess: widget.spocClassroomAccess,
      filesAccess: widget.spocFilesAccess,
      onFetchSigninQr: widget.onFetchSigninQr,
      onSaveSigninQr: widget.onSaveSigninQr,
      onCheckSigninStatus: widget.onCheckSigninStatus,
    ),
  );

  Widget _courseEntries(String? term, Widget child) =>
      CourseHubEntries.wrap(widget.courseHub, term, child, (key) {
        if (mounted) _openHub(CourseHubPage.course, key);
      });
}
