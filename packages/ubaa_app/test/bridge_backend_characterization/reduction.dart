part of '../bridge_backend_characterization_test.dart';

void registerBridgeBackendReductionCharacterization() {
  test('全部功能与视图归约固定空教室课表特例和空结果语义', () async {
    final client = _CharacterizationBridgeClient(emptyReads: true);
    final backend = BridgeBackend(client);
    var pairCount = 0;

    for (final feature in FeatureId.values) {
      for (final view in FeatureQueryView.values) {
        pairCount += 1;
        final supported =
            feature == FeatureId.classroom ||
            _supportedViews[feature]!.contains(view);
        try {
          final result = await backend.loadFeatureQuery(
            feature,
            FeatureQuery(
              term: '2026-fall',
              date: DateTime(2026, 9, 4),
              campus: 2,
              week: 4,
              page: 0,
              size: 0,
              view: view,
              premisesId: 'premises-1',
              storeyId: 'storey-1',
              areaId: 'area-1',
              startTime: '08:00',
              endTime: '10:00',
              segment: '1',
              siteId: 7,
              orderId: 9,
              assignmentId: 'assignment-1',
              courseId: '42',
              judgeKeys: const <JudgeAssignmentQueryKey>[
                JudgeAssignmentQueryKey(
                  courseId: 'course-1',
                  assignmentId: 'assignment-1',
                ),
              ],
              includeExpired: true,
            ),
          );
          expect(supported, isTrue, reason: '${feature.name}/${view.name}');
          expect(
            result.isEmpty,
            !_successDespiteEmpty.contains(_featureViewKey(feature, view)),
            reason: '${feature.name}/${view.name}',
          );
          expect(result.resolvedRoute, ConnectionMode.webvpn);
        } on BackendException catch (error) {
          expect(supported, isFalse, reason: '${feature.name}/${view.name}');
          expect(error.code, UbaaErrorCode.invalidInput);
        }
      }
    }

    expect(pairCount, FeatureId.values.length * FeatureQueryView.values.length);
    expect(
      client.calls.where((call) => call.startsWith('classroomSearch:')),
      hasLength(FeatureQueryView.values.length),
    );
    expect(
      client.calls.where(
        (call) => call == 'scheduleWeek:term=2026-fall,week=4',
      ),
      hasLength(2),
      reason: 'summary(term+week) 与 scheduleWeek 都走周课表',
    );

    client.calls.clear();
    final plainSummary = await backend.loadFeatureQuery(
      FeatureId.schedule,
      const FeatureQuery(),
    );
    expect(client.calls, <String>['scheduleToday']);
    expect(plainSummary.isEmpty, isTrue);
  });
}

const _supportedViews = <FeatureId, Set<FeatureQueryView>>{
  FeatureId.schedule: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.scheduleToday,
    FeatureQueryView.scheduleTerms,
    FeatureQueryView.scheduleWeeks,
    FeatureQueryView.scheduleWeek,
  },
  FeatureId.exam: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.examArranged,
    FeatureQueryView.examNotArranged,
  },
  FeatureId.grades: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.gradesScored,
    FeatureQueryView.gradesMissing,
  },
  FeatureId.bykc: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.bykcDetail,
    FeatureQueryView.bykcProfile,
    FeatureQueryView.bykcChosenCourses,
    FeatureQueryView.bykcStatistics,
  },
  FeatureId.classroom: <FeatureQueryView>{},
  FeatureId.spoc: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.spocDetail,
  },
  FeatureId.judge: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.judgeDetail,
    FeatureQueryView.judgeBatchDetails,
  },
  FeatureId.libbook: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.libbookAreas,
    FeatureQueryView.libbookAreaDetail,
    FeatureQueryView.libbookSeats,
    FeatureQueryView.libbookBookings,
  },
  FeatureId.signin: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.signinPending,
    FeatureQueryView.signinCompleted,
  },
  FeatureId.cgyy: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.cgyyPurposeTypes,
    FeatureQueryView.cgyyDayInfo,
    FeatureQueryView.cgyyOrders,
    FeatureQueryView.cgyyOrderDetail,
    FeatureQueryView.cgyyLockCode,
  },
  FeatureId.ygdk: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.ygdkRecords,
  },
  FeatureId.evaluation: <FeatureQueryView>{
    FeatureQueryView.summary,
    FeatureQueryView.evaluationPending,
  },
};

const _successDespiteEmpty = <String>{
  'bykc/bykcDetail',
  'bykc/bykcProfile',
  'spoc/spocDetail',
  'judge/judgeDetail',
  'judge/judgeBatchDetails',
  'libbook/libbookAreaDetail',
  'cgyy/cgyyPurposeTypes',
  'cgyy/cgyyOrderDetail',
  'cgyy/cgyyLockCode',
  'ygdk/summary',
  'evaluation/summary',
  'evaluation/evaluationPending',
};

String _featureViewKey(FeatureId feature, FeatureQueryView view) =>
    '${feature.name}/${view.name}';
