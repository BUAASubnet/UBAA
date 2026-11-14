// 由 docs/site/tech/privacy-policy.md 生成。
import 'policy.dart';

const bundledPrivacyPolicy = PrivacyPolicyDocument(
  version: 5,
  title: '隐私政策',
  blocks: <PrivacyPolicyBlock>[
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '本政策说明 UBAA 如何处理学校账号、会话、业务数据、更新与公告请求和产品改进统计。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '学校账号与业务请求',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '登录所需的账号、密码与验证码用于向学校认证系统验证身份。课表、成绩、作业和预约等请求由设备通过直连或学校 WebVPN 发起，不经过 UBAA 的服务器中转。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '登录过程产生的会话与 Cookie 用于后续访问学校系统。选择阳光打卡照片并提交时，照片会上传到学校业务系统。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '设备上的保存',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text: '勾选记住密码后，应用通过设备安全存储保存相应凭据，供后续登录使用。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text: '应用保留本地会话与配置，以恢复登录和连接状态。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text: '业务数据可能保存在加密缓存中，用于再次打开或离线查看。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text:
          '页面偏好和本地账号信息用于恢复使用状态。外观主题是独立的设备偏好，保存在普通本地偏好存储中，不包含账号凭据，也不随退出或清除账号删除。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '设置页提供缓存清理、退出登录及清除已保存账号等操作，作用范围以操作提示为准。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '本次运行诊断',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '本次运行诊断保存在内存中，用于说明本次运行的错误类别，不会自动上传。反馈问题前请检查拟发送的文字和截图。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '更新检查与公告',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '支持应用服务的版本默认请求更新信息和公告。请求只发送接口版本、应用版本、设备平台和分发渠道，不携带安装 ID、用户标识或学校 Cookie，也不计入产品改进统计。关闭统计不影响更新检查和公告。旧版已保存的基础模式不发送此类请求。公告已读记录仅保存在本机。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '产品改进统计',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '支持应用服务的版本默认开启产品改进统计，应用启动时不再弹出隐私选择。您可以通过设置中的“产品改进统计”开关选择是否参与，并在项目网站查阅本政策。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '我们使用以下数据监测学校接口可用性、定位缺陷、改进功能，并统计使用人数和年级分布：',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text: '随机生成的安装 ID，用于区分安装和处理删除请求。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text:
          '根据已确认的学校账号在设备上计算的学号派生标识、年级类型和入学年份。无法识别年级时记为未知。派生标识用于跨设备去重，仍属于个人信息。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text: '平台、分发渠道、版本和使用方式（图形界面或命令模式）。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text:
          '按校园日期汇总的功能使用次数、连接路线、结果、稳定错误码及分类、耗时区间和有限的源码位置。崩溃只记录异常类型或固定的 panic 错误码，以及符合规则的一处源码位置（如果有）。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text:
          '按分钟汇总的登录发起、成功、失败次数和各功能的加载次数及结果，用于查看一天中的使用曲线。设备只上传“当天第几分钟”和次数；服务端把所有设备的次数按分钟、平台和渠道合并保存，不保存安装 ID、用户标识或版本。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '统计不会上传学号原文、姓名、密码、验证码、Cookie、Token、URL、HTTP 正文、课程、成绩、文件名、照片、位置、诊断报告、本机路径、完整堆栈或异常消息。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '统计数据的处理与保存',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '统计数据通过 HTTPS 直接传输给 UBAA 维护者位于中国大陆的服务器，并在该服务器上处理和保存。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '设备在本地对学号加盐计算 SHA-256。接收统计的服务 用独立密钥对收到的派生标识再计算 HMAC-SHA256，数据库只保存第二次计算得到的标识。网络地址只临时用于限流，UBAA 的统计库和 服务请求日志不保存 IP 地址。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '活跃明细保留 13 个月，功能、错误和耗时明细保留 90 天，按分钟汇总的次数保留 30 天。用于去重的批次记录保留 14 天，删除标记保留 30 天。没有安装 ID 或用户标识的汇总数据长期保留。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '关闭统计与数据请求',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '在设置中关闭“产品改进统计”会停止收集和上传，并清空设备中尚未确认上传完成的数据。已上传的数据按上述保留期处理；如需提出撤回或删除请求，请通过下方联系方式联系维护者。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '已上传明细按安装 ID 区分。未定稿的汇总会在后续计算中反映明细删除；已定稿的汇总没有安装 ID 或用户标识，保留原值。按分钟汇总的次数同样没有安装 ID 或用户标识，无法按设备删除，会在 30 天后自动清除。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '隐私政策更新后，应用保留您先前保存的统计开关和基础模式选择。旧版基础模式用户可以通过“产品改进统计”开关确认后重新启用。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '联系维护者',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '如对本政策有疑问，或需要协助关闭、撤回或删除统计数据，请通过 UBAA 项目的 GitHub Issues（https://github.com/BUAASubnet/UBAA/issues） 联系维护者。发现安全漏洞时，请使用 GitHub 私有漏洞报告（https://github.com/BUAASubnet/UBAA/security/advisories/new）。不要在公开渠道发布账号、密码、验证码、预约门锁信息或个人资料。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '文档网站',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '文档网站无需学校账号，不提供校园登录表单。访问网站时，托管与网络服务商可能按其服务规则处理访问日志；这与应用中的学校登录和业务数据处理分别发生。',
    ),
  ],
  changes: <String>['产品改进统计改由维护者位于中国大陆的服务器处理和保存。'],
);
