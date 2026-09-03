/// 首页和普通功能页中展示的只读功能。
enum FeatureId {
  schedule,
  exam,
  grades,
  bykc,
  classroom,
  spoc,
  judge,
  libbook,
  signin,
  cgyy,
  ygdk,
  evaluation,
}

/// 普通功能页的稳定顺序。
const ordinaryFeatureIds = <FeatureId>[
  FeatureId.schedule,
  FeatureId.exam,
  FeatureId.grades,
  FeatureId.bykc,
  FeatureId.classroom,
  FeatureId.spoc,
  FeatureId.judge,
  FeatureId.libbook,
];

/// 高级功能页的稳定顺序。
const advancedFeatureIds = <FeatureId>[
  FeatureId.signin,
  FeatureId.cgyy,
  FeatureId.ygdk,
  FeatureId.evaluation,
];

extension FeatureIdText on FeatureId {
  String get title => switch (this) {
    FeatureId.schedule => '课表查询',
    FeatureId.exam => '考试查询',
    FeatureId.grades => '成绩查询',
    FeatureId.bykc => '博雅课程',
    FeatureId.classroom => '空教室查询',
    FeatureId.spoc => 'SPOC作业',
    FeatureId.judge => '希冀作业',
    FeatureId.libbook => '图书馆座位',
    FeatureId.signin => '课堂签到',
    FeatureId.cgyy => '场馆预约',
    FeatureId.ygdk => '阳光打卡',
    FeatureId.evaluation => '教学评教',
  };

  String get description => switch (this) {
    FeatureId.schedule => '查看课程表，支持周视图和学期切换',
    FeatureId.exam => '查看考试安排，支持学期切换',
    FeatureId.grades => '查看课程成绩、学分和绩点',
    FeatureId.bykc => '浏览选课，查看已选课程',
    FeatureId.classroom => '查询各校区空闲教室',
    FeatureId.spoc => '查看当前学期作业与提交状态',
    FeatureId.judge => '聚合希冀平台作业与提交进度',
    FeatureId.libbook => '查看图书馆座位和预约记录',
    FeatureId.signin => '查看今日课程签到状态',
    FeatureId.cgyy => '查看场馆站点、日期和预约订单',
    FeatureId.ygdk => '查看学期进度与打卡记录',
    FeatureId.evaluation => '查看待评课程和完成进度',
  };

  String get wireName => switch (this) {
    FeatureId.schedule => 'schedule',
    FeatureId.exam => 'exam',
    FeatureId.grades => 'grades',
    FeatureId.bykc => 'bykc',
    FeatureId.classroom => 'classroom',
    FeatureId.spoc => 'spoc',
    FeatureId.judge => 'judge',
    FeatureId.libbook => 'libbook',
    FeatureId.signin => 'signin',
    FeatureId.cgyy => 'cgyy',
    FeatureId.ygdk => 'ygdk',
    FeatureId.evaluation => 'evaluation',
  };
}
