// 由 docs/site/tech/privacy-policy.md 生成。
import 'policy.dart';

const bundledPrivacyPolicy = PrivacyPolicyDocument(
  version: 1,
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
          '登录所需的账号、密码与验证码用于向学校认证系统验证身份。课表、成绩、作业和预约等请求由设备通过直连或学校 WebVPN 发起，不经旧版 UBAA 中转服务器。',
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
          '您同意本政策后，图形界面会向 UBAA 应用服务请求更新信息和公告。请求只发送接口版本、应用版本、设备平台和分发渠道，不携带安装 ID、用户标识或学校 Cookie，也不计入产品改进统计。关闭统计不影响更新检查和公告；撤回同意后不再发送此类请求。公告已读记录仅保存在本机。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '产品改进统计',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '支持应用服务的版本会在取得同意后启用产品改进统计，第一次同意时默认打开。您可以关闭统计，或者选择不同意并使用基础模式。',
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
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '统计不会上传学号原文、姓名、密码、验证码、Cookie、Token、URL、HTTP 正文、课程、成绩、文件名、照片、位置、诊断报告、本机路径、完整堆栈或异常消息。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '统计数据的境外处理',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '接收方为 Cloudflare, Inc.。统计数据通过 HTTPS 传输，在中国大陆境外的 Cloudflare Worker 和 D1 数据库中处理和存储。正式启用前，项目维护者会在本政策公布实际存储地点和接收方的联系方式。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '设备在本地对学号加盐计算 SHA-256。接收统计的 Worker 用独立密钥对收到的派生标识再计算 HMAC-SHA256，数据库只保存第二次计算得到的标识。网络地址只临时用于限流，UBAA 的统计库和 Worker 请求日志不保存 IP 地址。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '活跃明细保留 13 个月，功能、错误和耗时明细保留 90 天。用于去重的批次记录保留 14 天，删除标记保留 30 天。没有安装 ID 或用户标识的汇总数据长期保留。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '关闭、撤回与删除',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text: '在设置中关闭“产品改进统计”会停止收集和上传，并清空设备中尚未确认上传完成的数据。已上传的数据可以单独删除。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text: '在设置中撤回同意会进入基础模式，停止统计、更新检查和公告等应用服务请求，删除请求仍可发送。撤回不影响学校功能和设备上的本地功能。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text:
          '“删除已上传的统计数据”会请求清除当前安装 ID 对应的服务端明细。删除未完成时，应用会暂停上传并重试。未定稿的汇总会在后续计算中反映删除；已定稿的汇总没有安装 ID 或用户标识，保留原值。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '隐私政策的重要内容发生变化时，应用会请您重新选择。重新同意时会保留您先前保存的统计开关。',
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
  changes: <String>[
    '首次说明产品改进统计的收集范围、境外处理和保留期限。',
    '说明更新检查和公告请求发送的版本与平台信息。',
    '说明如何关闭统计、撤回同意和删除已上传的统计数据。',
  ],
);
