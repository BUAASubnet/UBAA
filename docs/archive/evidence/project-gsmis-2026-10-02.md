# GSMIS课表与完整时间轴证据

日期：2026-10-02，起点`178a4591`，本提交候选。逐操作九列、当前两来源及明确边界见[GSMIS来源](../source-parity-gsmis-2026-10-02.md)。

## 行为闭合

先观察GSMIS学期包装进入本科解析的ParseError RED，再实现完整学期校验、官方入口/空POST/精确有序表单、同路线Cookie与有界重定向。首次本科失败后实际核验GSMIS，仅成功后为当前路线/会话代次记录来源；新会话不能复用旧标记。校历由SCSKRQ与mask交叉核对唯一周一，未知校历/学期/节次/时间拒绝；同班、地点、教师、mask、方案内去重并仅合并相邻节次。6项GSMIS parser/Mock专项通过。

空周时间轴在390/834/1280三宽度先实际缺少08:00而RED；贯穿Bridge、App、普通缓存投影、完整导入持久化及UI后，13项新旧课表UI回归通过。时间轴沿旧52宽显示开始/结束，冲突为--:--；旧研究生缓存仅在标准方案条件全部匹配时补14节，不猜其它方案。真实缓存关闭重开验证节次元数据保留，原取得时间与路线不改。

CLI schema升v11、Bridge升v40，旧缓存缺sectionTimes默认空。原普通本科包装容错保持；完整导入仍不保存未证实结果。已有失败Mock补充显式GSMIS失败响应，保留缓存保护、会话失效及零重发原断言，没有删除旧回归。

## 当前门禁

完整just check（Rust、CLI/二进制端到端、结构、Clippy、文档）、敏感检查、FRB零漂移通过。完整七包Flutter分析及1312项测试通过（57/92/627/339/31/91/75）。额外Core全套、116项facade、61项只读测试支持、51项App缓存/投影及生成合同均通过。没有更新golden来掩盖失败。

## 实时边界

当前候选just verify-live mode=webvpn退出0，38项PASS、0项FAIL，学校业务写入0；研讨室用途仍明确static_fallback。真实账号此次课表走本科来源，因此只证明现有读取无回归，不能当作GSMIS真实账号证据。没有Direct矩阵、真实验证码答案提交或真实门锁密码数据。生产App与Computer Use在最终候选另行验收。

## 仓库外日志指纹

日志根：`<private-evidence>/project-review-20261002-resume`。

| 文件 | SHA-256 |
|---|---|
| `gsmis-red.log` | `5b73a5039fd233616dca24ebee0e55a468b270023a7da0e26a6f81bf45e20c54` |
| `gsmis-network2.log` | `f436154e259deaeb8134e5c0f6b86321aa49fc485f4fc9122fb7b8e2ef483b1c` |
| `gsmis-ui-red.log` | `5f081405bf753f7447f5cf6141ff74b86e3fc16b55c5e1de66e0924a5f114df6` |
| `gsmis-ui-green2.log` | `2420bac7a4f2a9d4e91e6ebf66855130d50fbfa10096d05fa02b9a5bc53aa382` |
| `gsmis-core-all2.log` | `a2819c6652a0929a4cea41b71381d5d9c2a51ce46910c8513a8be13484d3df8f` |
| `gsmis-check2.log` | `d2c73a61c7400c46eaecd2a9e68e88121ae61ea5e73739446e3e00dffa371d30` |
| `gsmis-flutter.log` | `983b0cd821ead99e75296199f4ccede55e504495b0e12b58989a1f196e7d6d5c` |
| `gsmis-codegen-check.log` | `29063bdcf4962eb7dbf36303bd3c806720ae2c385578437c6f7eec590155f91f` |
| `gsmis-sensitive.log` | `bfe8d4ecc9c20ae08c4df3df9f3605096fee85a2aee919c8582f14173f5f4672` |
| `gsmis-webvpn.log` | `24c69e7167850de860a8534fc96d4ac26faf7898787e9b1ce80a20e47d520691` |
