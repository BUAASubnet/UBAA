import 'package:ubaa_domain/ubaa_domain.dart';

String previewDay(DateTime date) => date.toIso8601String().substring(0, 10);

/// 全部课程、成绩和教室均为虚构；日期围绕运行当天生成。
FeatureResult previewAcademic(FeatureId feature, FeatureQuery q, String state) {
  final now = homeCampusTime(DateTime.now());
  final monday = DateTime(now.year, now.month, now.day - now.weekday + 1 - 49);
  final term = q.term ?? 'preview-current';
  final details = <FeatureDetail>[];
  FeatureOverview? overview;
  String title(String s) => state == 'long' ? '$s——合成跨学科探索实践与长标题换行预览' : s;
  void add(String name, FeaturePresentation p) =>
      details.add(FeatureDetail(title: title(name), presentation: p));
  if (q.view == FeatureQueryView.scheduleTerms) {
    for (var i = 0; i < 3; i++) {
      add(
        '合成${i == 0 ? '当前' : '往期 $i'}学期',
        TermPresentation(
          code: i == 0 ? 'preview-current' : 'preview-past-$i',
          selected: i == 0,
          index: i + 1,
        ),
      );
    }
  } else if (q.view == FeatureQueryView.scheduleWeeks) {
    for (var w = 1; w <= 18; w++) {
      add(
        '第 $w 周',
        WeekPresentation(
          requestTerm: term,
          responseTerm: term,
          number: w,
          current: w == 8,
          startDate: previewDay(monday.add(Duration(days: (w - 1) * 7))),
          endDate: previewDay(monday.add(Duration(days: (w - 1) * 7 + 6))),
        ),
      );
    }
  } else if (feature == FeatureId.schedule) {
    final times = scheduleSectionTimes(courses: []);
    overview = ScheduleWeekOverview(code: term, sectionTimes: times);
    for (var i = 0; i < (state == 'many' ? 28 : 11); i++) {
      final begin = [1, 3, 6, 8, 11, 13][i % 6];
      add(
        '合成课程 ${i + 1}',
        ScheduleCoursePresentation(
          courseCode: '$term-course-$i',
          courseSerialNo: 'SYN-$i',
          credit: '2.0',
          dayOfWeek: i == 10 ? 6 : i % 5 + 1,
          beginSection: begin,
          endSection: begin + 1,
          beginTime: times[begin - 1].start,
          endTime: times[begin].end,
          place: '合成教学楼 ${101 + i}',
          weeksAndTeachers: '1–18 周 · 合成教师 ${i + 1}',
        ),
      );
    }
    if (state == 'long' || state == 'many') {
      add(
        '合成时间待定课程',
        const ScheduleCoursePresentation(courseCode: 'preview-tbd'),
      );
    }
  } else if (feature == FeatureId.exam) {
    for (var i = 0; i < 6; i++) {
      final arranged = i < 4;
      if (q.view == FeatureQueryView.examArranged && !arranged ||
          q.view == FeatureQueryView.examNotArranged && arranged) {
        continue;
      }
      final date = now.add(Duration(days: [-2, 1, 7, 14, 20, 21][i]));
      add(
        '合成考核 ${i + 1}',
        ExamPresentation(
          arranged: arranged,
          courseNo: 'EX-$i',
          date: arranged ? previewDay(date) : null,
          startTime: arranged ? '14:00' : null,
          endTime: arranged ? '16:00' : null,
          place: arranged ? '合成考场 ${201 + i}' : null,
          seat: arranged ? '${10 + i}' : null,
          taskId: 'exam-$i',
          type: '合成期末考试',
        ),
      );
    }
  } else if (feature == FeatureId.grades) {
    final grades = [
      for (var i = 0; i < (state == 'many' ? 48 : 10); i++)
        GradePresentation(
          courseName: title('合成课程 ${i + 1}'),
          courseCode: '$term-G-$i',
          termCode: term,
          score: term == 'preview-current' && i > 6
              ? null
              : i % 3 == 0
              ? '优秀'
              : '${75 + i % 20}',
          gradePoint: '3.5',
          credit: 2,
          courseType: i.isEven ? '必修' : '选修',
          scoreType: i % 3 == 0 ? '等级制' : '百分制',
        ),
    ];
    overview = GradesTermOverview(
      requestTerm: term,
      termCode: term,
      grades: state == 'empty' ? [] : grades,
    );
    for (final g in grades) {
      if (q.view == FeatureQueryView.gradesScored && g.score == null ||
          q.view == FeatureQueryView.gradesMissing && g.score != null) {
        continue;
      }
      add(g.courseName!, g);
    }
  } else if (feature == FeatureId.classroom) {
    final campus = q.campus ?? 1;
    for (var building = 1; building <= 4; building++) {
      for (var room = 1; room <= (state == 'many' ? 20 : 8); room++) {
        add(
          '合成教室 $building${room.toString().padLeft(2, '0')}',
          ClassroomPresentation(
            roomId: 'preview-$campus-$building-$room',
            floorId: 'preview-$campus-$building',
            floorName: '${campus == 1 ? '学院路' : '沙河'}合成教学楼 $building',
            availableSections: room.isEven
                ? '1,2,3,6,7,8'
                : '4,5,9,10,11,12,13,14',
            queryDate: previewDay(q.date ?? now),
            campus: campus,
          ),
        );
      }
    }
  }
  if (feature == FeatureId.schedule &&
      (q.view == FeatureQueryView.scheduleToday ||
          q.view == FeatureQueryView.summary)) {
    final day = q.date ?? now;
    final week = WeekPresentation(
      requestTerm: term,
      responseTerm: term,
      number: 8,
      current: true,
      startDate: previewDay(monday.add(const Duration(days: 49))),
      endDate: previewDay(monday.add(const Duration(days: 55))),
    );
    return homeProjectScheduleDay(
      FeatureResult.success(
        details: state == 'empty' ? [] : details,
        resolvedRoute: ConnectionMode.direct,
      ),
      week,
      day,
    );
  }
  if (state == 'empty' &&
      q.view != FeatureQueryView.scheduleTerms &&
      q.view != FeatureQueryView.scheduleWeeks) {
    details.clear();
  }
  return FeatureResult.success(
    details: details,
    overview: overview,
    resolvedRoute: ConnectionMode.direct,
  );
}
