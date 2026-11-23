// 由 docs/site/tech/privacy-policy.md 生成。
import 'policy.dart';

const bundledPrivacyPolicy = PrivacyPolicyDocument(
  version: 9,
  title: '隐私政策',
  blocks: <PrivacyPolicyBlock>[
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '生效日期：2026 年 11 月 23 日。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '本政策说明 UBAA 如何处理学校账号、会话、业务数据、更新与公告请求和产品改进统计。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.heading,
      level: 2,
      text: '开发者信息',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '应用名称：UBAA。开发者：BUAASubnet。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: 'UBAA 是学生开发的第三方工具，与北京航空航天大学官方无隶属或授权关系。',
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
      bold: <(int, int)>[(0, 28)],
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: '登录过程产生的会话与 Cookie 用于后续访问学校系统。选择阳光打卡照片并提交时，照片会上传到学校业务系统。',
      bold: <(int, int)>[(29, 55)],
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
      text:
          '本地诊断保存最近七天内最多 100 条错误记录，用于定位读取、提交和启动的失败阶段和原因。完整诊断报告和本地错误编号不会自动上传。反馈问题前请检查拟发送的文字和截图。',
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
          '支持应用服务的版本仅在您同意本政策后请求更新信息和公告。请求只发送接口版本、应用版本、设备平台和分发渠道，不携带安装 ID、用户标识或学校 Cookie，也不计入产品改进统计。关闭统计不影响更新检查和公告。旧版已保存的基础模式不发送此类请求。公告已读记录仅保存在本机。',
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
          '首次使用或政策升级后，您需要阅读并同意本政策才能登录或恢复会话。不同意时无法登录使用。支持应用服务的版本在您同意后开启产品改进统计，您可以随时在设置中关闭。已有基础模式保持关闭，除非您在设置中主动开启。',
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
      bold: <(int, int)>[(0, 34)],
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
          '按校园日期汇总的功能打开、读取和写入次数、连接路线、结果、稳定错误码及分类、耗时区间和有限的源码位置。只有您主动进入功能页才计一次打开。崩溃只记录异常类型或固定的 panic 错误码，以及符合规则的一处源码位置（如果有）。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.bullet,
      level: 0,
      text:
          '按分钟汇总的登录发起、成功、失败次数，各功能的打开次数，以及按结果统计的功能加载次数，用于查看一天中的使用曲线。设备只上传“当天第几分钟”和次数；服务端把所有设备的次数按分钟、平台和渠道合并保存，不保存安装 ID、用户标识或版本。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text:
          '错误统计还可以附带 Core 源码位置、失败阶段与原因、HTTP 状态、响应长度与类别、JSON 字段类型和解析行列。上游业务码只保留有界数字；业务提示只保留经过逐字确认不含个人数据的固定说明。未知错误正文、业务字段值和响应全文不上传。相同错误维度只保留最新样本，服务端样本保留 14 天。公开看板仅展示汇总，安全诊断样本仅供授权维护者查看。',
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
      text: '如您此前要求删除统计数据，应用会继续发送删除请求直到完成。',
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
          '请通过 UBAA 项目的 GitHub Issues（https://github.com/BUAASubnet/UBAA/issues） 联系维护者。维护者在 15 个工作日内答复并处理查阅、复制、更正、删除个人信息及撤回同意的请求。请勿在公开渠道发布账号、密码、验证码、预约门锁信息或个人资料。',
    ),
    PrivacyPolicyBlock(
      kind: PrivacyPolicyBlockKind.paragraph,
      level: 0,
      text: 'UBAA 不提供独立账号注册。退出登录并清除已保存账号，即可删除本机账号数据。',
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
  changes: <String>['产品改进统计按天和按分钟汇总主动打开各功能的次数，与功能加载次数分开统计。'],
);
