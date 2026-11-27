part of 'shell.dart';

enum _HubPage {
  course('课程主页'),
  assignments('全部作业'),
  sources('按来源浏览');

  const _HubPage(this.title);
  final String title;
}

extension _ShellCourseHub on _UbaaMainShellState {
  void _openHub(_HubPage page, [String? key]) {
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
      onCourse: (key) => _openHub(_HubPage.course, key),
      onAssignments: () => _openHub(_HubPage.assignments),
      onSources: () => _openHub(_HubPage.sources),
    );
  }

  Widget _buildHubPage() => ValueListenableBuilder(
    valueListenable: widget.courseHub!,
    builder: (_, snapshot, _) => switch (_hubPage!) {
      _HubPage.course when _courseTerm != snapshot.termCode => const Center(
        child: Text('课程所属学期已变化'),
      ),
      _HubPage.course => CourseHubCoursePage(
        courseKey: _courseKey!,
        snapshot: snapshot,
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
      _HubPage.assignments => CourseHubAssignmentsPage(
        snapshot: snapshot,
        onOpenAssignment: _openHomeNavigation,
        onRefresh: widget.onRefreshCourseHub,
      ),
      _HubPage.sources => CourseHubSourcesPage(
        snapshot: snapshot,
        onOpenFeature: _openFeatureList,
      ),
    },
  );

  Widget _courseEntries(String? term, Widget child) =>
      CourseHubEntries.wrap(widget.courseHub, term, child, (key) {
        if (mounted) _openHub(_HubPage.course, key);
      });
}
