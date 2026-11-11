# 成绩变化基线统一加密（P4-AH）

2026-09-23，基于`fff8611e`。双冻结来源逐操作对照先于生产改动，见[source-parity](../source-parity-offline-recovery-2026-09-17.md)。学校HTTP、Cookie和写操作合同不变；Bridge同步升为v36，缓存SQL/schema保持v6，新增独立白名单载荷。

生产首页的成绩比较基线改用Core统一AES-GCM仓库，按本机账号、实际路线、精确学期隔离。一次本地操作返回原基线并保存新完整观察，不取得网络锁；空集合、不完整或持久来源不建立新出分观察，容量/密钥/清理/退出故障不回退明文。旧ui-grade-scores.json禁止写入新成绩，确认加密保存后才移除对应旧范围；其他账号/路线保留，旧学期独立迁入，不覆盖既有加密值。迁移期间文件变化或格式损坏保留原文件并提示本机问题。

观察到3项行为RED：旧文件会新增明文、Core缺少独立基线范围、显式缓存清理后旧提醒仍保留。最小修复后Core5项、平台8项、控制器8项、Dart Bridge映射3项、Bridge本地通道1项和首页反馈通过。另保留测试装配编译错误、初轮门禁文档版本未同步、Clippy局部helper位置错误及清理测试的异步边界回归；没有将它们算作预期行为RED。清理未配置旧存储时不增加无意义的异步边界，原测试断言保持。

完整Flutter1099项（57+75+560+287+23+42+55）和7包静态分析通过；随后收窄显式backendFactory的默认旧文件读取范围，Host42项单独重验通过。just check通过，包含CLI端到端16项、Bridge140项（2项独立进程测试按既有配置ignored）；本轮聚焦Bridge测试另通过。refs/layout/敏感扫描、FRB零漂移通过。生成入口使用packages/ubaa_bindings工作目录和固定2.13.0。

macOS最终100项、iPhone17Pro/iOS26.5模拟器100项原生矩阵通过，新基线typed FFI、密文重开、精确范围和跨句柄退出栅栏均实际执行；macOS旧成绩提醒界面12项通过，重开存储/宿主、账号/路线、查看/忽略和清除错误原断言保留，底层已换真实Core加密。iPadPro13M5/iOS26.5模拟器同代码100项通过。

这些属于确定性、原生FFI与合成界面证据；不是实体设备性能、真实学校App新链路或发布证据。正式三端30次、完整首页刷新成本、最终Direct/WebVPN仍待闭合。“退出并清除”的提醒偏好遗漏将独立修复。

日志在仓库外私有目录`p4ah-grade-baseline-20260923`；不含真实账号输入或学校原始响应。

| 文件 | SHA-256 |
|---|---|
| `ubaa-p4ah-app-bridge.log` | `26b801db2c129dc9134f95826db33475f5226ec6c50cda91a53f021878f89ab6` |
| `ubaa-p4ah-app-initial.log` | `ae597fd4bb55c9d46069ce803d3536e438412ec57ec92949cc69eddaa8016166` |
| `ubaa-p4ah-app-red.log` | `e5b46d810ca52da7a76b6f69b7e1175c439a4351c448fcfebb7213db8a227354` |
| `ubaa-p4ah-app.log` | `e4cb053f26078ffa30f8dd4d628e44fc875507d48e965022f0e4dc6217f9f2fc` |
| `ubaa-p4ah-bridge.log` | `d1833708969b7bf8e35e1b0f4443b7ea43b3794a4ba1d75711e8e0b9a3f4f87a` |
| `ubaa-p4ah-check-final.log` | `b3bbb8d34dd6ec0018028f8c7f470396b0c80825d0e065bb8eb6fe4d0e2b38e6` |
| `ubaa-p4ah-check-green.log` | `6c5d29c298a32ca33ce7f56054df280c216358b583cb49cb25e745c7a00384b4` |
| `ubaa-p4ah-check.log` | `5ada58b254d1ab15f09d98f32c95b7868e0ad9e7ea9fd747ddf2c4a368aa1d3c` |
| `ubaa-p4ah-codegen.log` | `eef3c35576858aad5366faffa2162a7a069324b253506d776bfb04933e21dca3` |
| `ubaa-p4ah-core-red.log` | `5764a3cc42478da4aede0293cd0ccdcbc628b4556c05bff9e15bbcbc6f81946b` |
| `ubaa-p4ah-core.log` | `5c9121ad9543ea9aaa61ffc20c19142c29d819ed6f9a49d5739e7d2db2a27ed4` |
| `ubaa-p4ah-flutter-final.log` | `3967caaccd8fc55e0233c023339e9a09013be2994bbda9f2c47660b57d77602a` |
| `ubaa-p4ah-flutter.log` | `74541c8300605b415f5b5b8a22dfea91bd8bec2f4b6ccf4d39f8f5b010a851c6` |
| `ubaa-p4ah-frb-check.log` | `29063bdcf4962eb7dbf36303bd3c806720ae2c385578437c6f7eec590155f91f` |
| `ubaa-p4ah-host-final.log` | `e153c346b4e53596cfd7b17e7930a9f51d6a0e19bbb10962b8efbd3327ec039e` |
| `ubaa-p4ah-layout.log` | `4f00b00a68dd8c9e6e16234e025883051e3585b02de206ac445d05f4d7b39498` |
| `ubaa-p4ah-native-grades.log` | `93098f395bf061fb46874cf1284be353818115b5126d5240b77f0807f41781b7` |
| `ubaa-p4ah-native-iphone.log` | `dc32f862a731bf6fbd6228a7eb074fe8f8f773c03cf23bf8a062ec66ee6e735e` |
| `ubaa-p4ah-native-macos-final.log` | `c9341bafe712a5e9c2264b581cb45777da75a06f7ce4c3186456f1aef13d415e` |
| `ubaa-p4ah-native-macos.log` | `ec7edb283a90d99306172b3563abc62805d9fcf9f95f99839b039243c232f4c5` |
| `ubaa-p4ah-platform-red.log` | `e6d494242ffbcda9001c951c0254d561cb2394ebf019015353c968d1272ee155` |
| `ubaa-p4ah-platform.log` | `5435483fe1e7adea8a41278f8c5b1450d380203ab29d3b561cd49d5306cdfea6` |
| `ubaa-p4ah-sensitive.log` | `f34a02c849c0de2d862aacfb600e4a1ffee585fcd416badbe73632c61f04b33d` |
| `ubaa-p4ah-ui.log` | `9802b9bc959010478d1519701a134de6f82a949d1fd9c4ca97dce3230768df8a` |
| `ubaa-p4ah-native-ipad.log` | `197fb68d650f06c937f4c6611a8db810bf0f956b297628b01d7d976cc123976f` |
