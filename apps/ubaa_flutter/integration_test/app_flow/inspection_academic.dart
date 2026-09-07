part of '../app_flow_test.dart';

extension _AcademicInspection on _InspectionBackend {
  List<FeatureDetail> _academicDetails(FeatureId feature, FeatureQuery q) {
    switch (feature) {
      case FeatureId.schedule:
        if (q.view == FeatureQueryView.scheduleTerms) {
          return [
            for (final (code, name, current, index) in [
              ('2026-2027-1', '2026–2027 学年秋季学期', true, 1),
              ('2025-2026-2', '2025–2026 学年春季学期', false, 2),
            ])
              _item(
                name,
                {'学期编码': code, '当前学期': current ? '是' : '否'},
                presentation: TermPresentation(
                  code: code,
                  selected: current,
                  index: index,
                ),
                readNavigation: FeatureReadNavigation(
                  feature: feature,
                  query: FeatureQuery(
                    view: FeatureQueryView.scheduleWeeks,
                    term: code,
                  ),
                ),
              ),
          ];
        }
        if (q.view == FeatureQueryView.scheduleWeeks) {
          final term = _required(q.term);
          return [
            for (var week = 1; week <= 4; week++)
              _item(
                '第 $week 周',
                {'周次': '$week', '当前周': week == 2 ? '是' : '否'},
                presentation: WeekPresentation(
                  requestTerm: term,
                  responseTerm: term,
                  number: week,
                  current: week == 2,
                  startDate: '2026-09-07',
                  endDate: '2026-09-13',
                ),
                readNavigation: FeatureReadNavigation(
                  feature: feature,
                  query: FeatureQuery(
                    view: FeatureQueryView.scheduleWeek,
                    term: term,
                    week: week,
                  ),
                ),
              ),
          ];
        }
        final weekly =
            q.view == FeatureQueryView.scheduleWeek ||
            (q.term != null && q.week != null);
        return [
          _item(
            '数据结构与算法',
            {'时间': '08:00–09:35', '地点': '合成教学楼 A203'},
            subtitle: 'CS-DEMO-01',
            presentation: weekly
                ? ScheduleCoursePresentation(
                    courseCode: 'CS-DEMO-01',
                    dayOfWeek: 2,
                    beginSection: 1,
                    endSection: 2,
                    beginTime: '08:00',
                    endTime: '09:35',
                    place: '合成教学楼 A203',
                    weeksAndTeachers: '第 ${q.week} 周 · 示例教师甲',
                    credit: '4.0',
                  )
                : const TodayCoursePresentation(
                    time: '08:00–09:35',
                    place: '合成教学楼 A203',
                  ),
          ),
          _item(
            '大学物理实验',
            {'时间': '14:00–15:35', '地点': '合成实验楼 B105'},
            subtitle: 'PH-DEMO-02',
            presentation: weekly
                ? const ScheduleCoursePresentation(
                    courseCode: 'PH-DEMO-02',
                    dayOfWeek: 4,
                    beginSection: 5,
                    endSection: 6,
                    beginTime: '14:00',
                    endTime: '15:35',
                    place: '合成实验楼 B105',
                    teachingTarget: '合成班级',
                  )
                : const TodayCoursePresentation(
                    time: '14:00–15:35',
                    place: '合成实验楼 B105',
                  ),
          ),
          if (weekly)
            _item(
              '跨学科实践（时间待确认）',
              {'地点': '合成实践中心'},
              presentation: const ScheduleCoursePresentation(
                courseCode: 'LAB-DEMO-03',
                dayOfWeek: 9,
                place: '合成实践中心',
              ),
            ),
        ];
      case FeatureId.exam:
        return [
          if (q.view != FeatureQueryView.examNotArranged)
            _item(
              '线性代数',
              {'时间': '09:00', '地点': '合成教学楼 A301', '座位': '18', '类型': '期末考试'},
              presentation: const ExamPresentation(
                arranged: true,
                date: '2026-12-23',
                startTime: '09:00',
                place: '合成教学楼 A301',
                seat: '18',
                type: '期末考试',
              ),
            ),
          if (q.view != FeatureQueryView.examArranged)
            _item(
              '概率论（时间待安排）',
              {'类型': '期末考试'},
              presentation: const ExamPresentation(
                arranged: false,
                type: '期末考试',
              ),
            ),
        ];
      case FeatureId.grades:
        return [
          if (q.view != FeatureQueryView.gradesMissing) ...[
            _item(
              '程序设计基础',
              {'成绩': '92', '绩点': '3.8', '学分': '4.0', '课程类型': '专业必修'},
              subtitle: 'CS-DEMO-00',
              presentation: GradePresentation(
                courseCode: 'CS-DEMO-00',
                score: '92',
                gradePoint: '3.8',
                credit: 4.0,
                courseType: '专业必修',
                termCode: q.term,
              ),
            ),
            _item(
              '综合实践',
              {'成绩': '通过', '绩点': '优秀', '学分': '2.0'},
              presentation: const GradePresentation(
                score: '通过',
                gradePoint: '优秀',
                credit: 2.0,
              ),
            ),
          ],
          if (q.view != FeatureQueryView.gradesScored)
            _item('学术写作', {
              '成绩': '未出分',
              '学分': '1.5',
            }, presentation: const GradePresentation(credit: 1.5)),
        ];
      case FeatureId.classroom:
        const rooms = [
          ClassroomPresentation(
            roomId: 'room-a201',
            floorId: 'F02',
            floorName: '合成教学楼 / 二层',
            availableSections: '1,2,5,6,9,10,13',
          ),
          ClassroomPresentation(
            roomId: 'room-b305',
            floorId: 'F03',
            floorName: '合成教学楼 / 三层',
            availableSections: '3,4,7,8',
          ),
        ];
        return [
          for (final room in rooms)
            if ((q.floorId == null ||
                    q.floorId!.isEmpty ||
                    room.floorId.toLowerCase() == q.floorId!.toLowerCase() ||
                    room.floorName.toLowerCase().contains(
                      q.floorId!.toLowerCase(),
                    )) &&
                (q.section == null ||
                    q.section!.isEmpty ||
                    room.sectionTokens.contains(q.section)))
              _item(
                room.roomId == 'room-a201' ? '合成教学楼 A201' : '合成教学楼 B305',
                {'可用节次': room.availableSections},
                presentation: room,
              ),
        ];
      default:
        throw StateError('非学业巡检领域');
    }
  }
}
