import 'package:ubaa_domain/ubaa_domain.dart';

import 'promo_data.dart';

const storePreviousTerm = '2025-2026-2';
const storeEarlierTerm = '2025-2026-1';

final class StoreAssignment {
  const StoreAssignment({
    required this.id,
    required this.courseCode,
    required this.title,
    required this.instructions,
    required this.week,
    required this.day,
    required this.dueTime,
    this.score,
  });

  final String id, courseCode, title, instructions, dueTime;
  final int week, day;
  final String? score;

  StoreCourse get course => storeCourse(courseCode);
  DateTime get date => storeDate(week, day);
  bool get submitted => score != null;
  String get statusLabel => submitted ? '已提交' : '未提交';

  FeatureReadNavigation get navigation => FeatureReadNavigation(
    feature: FeatureId.spoc,
    query: FeatureQuery(view: FeatureQueryView.spocDetail, assignmentId: id),
  );

  FeatureDetail detail({required bool expanded}) => FeatureDetail(
    title: title,
    subtitle: course.name,
    presentation: SpocAssignmentPresentation(
      courseId: courseCode,
      courseName: course.name,
      assignmentId: id,
      teacherName: course.teacher,
      startTime: '${storeDateKey(storeDate(week - 1, day))} 08:00',
      dueTime: '${storeDateKey(date)} $dueTime',
      score: score,
      status: submitted
          ? AssignmentSubmissionStatus.submitted
          : AssignmentSubmissionStatus.unsubmitted,
      statusText: statusLabel,
      contentPlainText: expanded ? instructions : null,
      submittedAt: submitted
          ? '${storeDateKey(date.subtract(const Duration(days: 2)))} 08:20'
          : null,
      isDetail: expanded,
    ),
    readNavigation: expanded ? null : navigation,
  );
}

const storeAssignments = <StoreAssignment>[
  StoreAssignment(
    id: 'lab-list-stack',
    courseCode: 'CS2105',
    title: '实验二：链表与栈',
    instructions: '实现单链表和顺序栈，用栈检查表达式中的括号是否配对。提交源代码与测试说明。',
    week: 3,
    day: 3,
    dueTime: '22:00',
  ),
  StoreAssignment(
    id: 'problem-sets',
    courseCode: 'MA2103',
    title: '习题三：集合与关系',
    instructions: '证明给出的关系是否为等价关系，并列出对应的等价类。',
    week: 3,
    day: 4,
    dueTime: '20:00',
  ),
  StoreAssignment(
    id: 'homework-probability',
    courseCode: 'MA2201',
    title: '作业二：条件概率',
    instructions: '完成条件概率和贝叶斯公式的练习题，写出关键推导步骤。',
    week: 3,
    day: 6,
    dueTime: '23:59',
  ),
  StoreAssignment(
    id: 'practice-file-index',
    courseCode: 'CS2190',
    title: '小项目：文件索引',
    instructions: '实现命令行文件索引工具，按文件扩展名统计数量和大小。',
    week: 4,
    day: 1,
    dueTime: '20:00',
  ),
  StoreAssignment(
    id: 'reading-aircraft',
    courseCode: 'AE1001',
    title: '阅读报告：飞机的升力',
    instructions: '结合阅读材料，说明翼型、迎角和飞行速度怎样影响升力。',
    week: 4,
    day: 2,
    dueTime: '22:00',
  ),
  StoreAssignment(
    id: 'lab-binary',
    courseCode: 'CS2101',
    title: '实验一：数据表示',
    instructions: '比较原码、反码和补码表示，记录加法运算中出现的溢出。',
    week: 3,
    day: 4,
    dueTime: '22:00',
    score: '96',
  ),
  StoreAssignment(
    id: 'reading-notes',
    courseCode: 'EN2003',
    title: '阅读笔记：科技与生活',
    instructions: '选择一篇英语科技短文，记录文章主旨和三处重要表达。',
    week: 2,
    day: 4,
    dueTime: '22:00',
    score: '92',
  ),
];

final class StoreExam {
  const StoreExam({
    required this.courseCode,
    required this.week,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.place,
    required this.seat,
    this.titleSuffix = '',
  });

  final String courseCode, startTime, endTime, place, seat, titleSuffix;
  final int week, day;

  StoreCourse get course => storeCourse(courseCode);
  DateTime get date => storeDate(week, day);
  String get title => '${course.name}$titleSuffix';

  FeatureReadNavigation get navigation => const FeatureReadNavigation(
    feature: FeatureId.exam,
    query: FeatureQuery(view: FeatureQueryView.examArranged, term: storeTerm),
  );

  FeatureDetail get detail => FeatureDetail(
    title: title,
    presentation: ExamPresentation(
      arranged: true,
      requestTerm: storeTerm,
      courseNo: courseCode,
      taskId: 'exam-$courseCode',
      date: storeDateKey(date),
      startTime: startTime,
      endTime: endTime,
      place: place,
      seat: seat,
      week: week,
      type: '闭卷',
    ),
  );
}

const storeExams = <StoreExam>[
  StoreExam(
    courseCode: 'MA2103',
    week: 6,
    day: 1,
    startTime: '19:00',
    endTime: '20:30',
    place: '主M305',
    seat: '18',
    titleSuffix: '（阶段测验）',
  ),
  StoreExam(
    courseCode: 'CS2101',
    week: 9,
    day: 5,
    startTime: '15:50',
    endTime: '17:25',
    place: '新主楼F201',
    seat: '24',
    titleSuffix: '（期中）',
  ),
  StoreExam(
    courseCode: 'MA2201',
    week: 10,
    day: 5,
    startTime: '14:00',
    endTime: '15:35',
    place: '主M403',
    seat: '11',
    titleSuffix: '（期中）',
  ),
  StoreExam(
    courseCode: 'AE1001',
    week: 16,
    day: 5,
    startTime: '09:50',
    endTime: '11:25',
    place: '新主楼A101',
    seat: '08',
  ),
];

List<GradePresentation> storeGrades(String term) => [
  if (term == storeTerm)
    for (final code in storeCourses.map((course) => course.code).toSet())
      GradePresentation(
        courseCode: code,
        courseName: storeCourse(code).name,
        credit: double.parse(storeCourse(code).credit),
        courseType: '必修',
        termCode: term,
      ),
  for (final (code, name, score, gpa, credit, type) in switch (term) {
    storePreviousTerm => const [
      ('CS2002', '操作系统', '95', '4.0', 4.0, '必修'),
      ('CS2003', '计算机网络', '92', '3.9', 3.5, '必修'),
      ('MA2001', '线性代数', '94', '4.0', 3.0, '必修'),
      ('CS2004', '数据库系统', '89', '3.7', 3.0, '必修'),
      ('EN2002', '大学英语Ⅱ', '91', '3.9', 2.0, '必修'),
      ('PE1002', '体育（游泳）', '88', '3.7', 0.5, '必修'),
      ('GE2008', '艺术鉴赏', '优秀', null, 1.0, '选修'),
    ],
    storeEarlierTerm => const [
      ('CS1001', '程序设计基础', '93', '3.9', 4.0, '必修'),
      ('MA1001', '高等数学Ⅰ', '90', '3.9', 5.0, '必修'),
      ('PH1001', '大学物理Ⅰ', '87', '3.7', 3.0, '必修'),
      ('EN2001', '大学英语Ⅰ', '91', '3.9', 2.0, '必修'),
    ],
    _ => const <(String, String, String, String?, double, String)>[],
  })
    GradePresentation(
      courseCode: code,
      courseName: name,
      score: score,
      gradePoint: gpa,
      credit: credit,
      courseType: type,
      scoreType: '正常',
      termCode: term,
    ),
];
