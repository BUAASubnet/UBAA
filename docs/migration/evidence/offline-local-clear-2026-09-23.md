# 退出清理偏好与迟到回调证据

日期：2026-09-23。P4-AI；基点1c71ad27，Bridge v36/schema v6不变。

生产“退出并清除”现在清理当前已核实账号username/schoolId下的提醒和旧成绩基线，保留其他账号。Controller保持退出栅栏直到宿主本地收尾结束；普通退出保留偏好，但旧回调在退出或同账号重登后不再有效。Core清除成功后才删除账号密钥；索引、缓存、会话、凭据、基线和提醒任一失败均向清除调用方传播，并继续尝试独立清理。确认文案列明缓存/基线/提醒范围。成绩本机故障文案兼容“已保存但旧文件清理失败”，不误称一定未保存。

双冻结来源逐操作核对先于修改；11项宿主行为RED全部观察到预期缺口，随后GREEN。完整Flutter1110项（57+75+560+287+23+53+55）及7包静态分析通过；最终脚本的前6包通过后，最后App包因旧提示文字断言失败，更新精确文案后完整55项重验通过。第一轮Host全回归发现旧测试在普通退出后调用旧页面继续清除；新增拒绝断言、显式重登取得当前页面后完成原清除断言，没有放开旧回调。上述失败日志保留。

just check通过，含CLI端到端16项、Bridge140项及原有2项子进程ignore配置；refs、layout零baseline、敏感扫描、FRB生成零漂移、集成入口分析通过。macOS、iPhone17Pro/iOS26.5模拟器、iPadPro13M5/iOS26.5模拟器各111项原生矩阵通过，包含新增11项清理行为。真实成绩只读验收辅助在读取加密基线后释放opaque句柄，已分析，真实学校执行另列。

这些是确定性与原生合成证据，不是学校成功、正式30次性能或发布证据。Computer Use已确认Mac解锁及模拟器窗口可访问。下一步补齐完整首页九来源计时、成本分解、真实双路线与三端启动测量，整体目标未完成。

日志在仓库外私有目录`p4ai-local-clear-20260923`，目录700/文件600，无真实响应或账号材料。

| 文件 | SHA-256 |
|---|---|
| `ubaa-p4ai-check.log` | `ef74977d2223f3e9d7e2239d000cc3ed705de1276db2bdf1ab07434dfdf4a8f9` |
| `ubaa-p4ai-flutter-app.log` | `82fd77f6ba2529f41b56369f1f404e2a7da40b9d304d472a416ae68e530ba9d6` |
| `ubaa-p4ai-flutter-final.log` | `670a8fbbde63ef4305e0a46e6a82a9334c8c7272ea33ecb9392078ca0f584809` |
| `ubaa-p4ai-flutter.log` | `97091a36b324266f232c2ced6821bde3e6eefbaa204de3d8fbe7d0168709873c` |
| `ubaa-p4ai-frb.log` | `29063bdcf4962eb7dbf36303bd3c806720ae2c385578437c6f7eec590155f91f` |
| `ubaa-p4ai-green.log` | `d1d7d63bfb35a5d55293f6bafd98145e890536215a44ed889167930e18ed28f3` |
| `ubaa-p4ai-integration-analyze.log` | `552b6bcd0251014c68da14bcb836a4b0c527608ff07cc4b015a747c3e8c6f790` |
| `ubaa-p4ai-layout-staged.log` | `4f00b00a68dd8c9e6e16234e025883051e3585b02de206ac445d05f4d7b39498` |
| `ubaa-p4ai-layout.log` | `4f00b00a68dd8c9e6e16234e025883051e3585b02de206ac445d05f4d7b39498` |
| `ubaa-p4ai-native-ipad.log` | `3d4050fa6696aa66f7154b64dedac1b8da259b40bc0f9c7154ce93ac66bb9285` |
| `ubaa-p4ai-native-iphone.log` | `63dae911c11e8216e5ec484ac00a2f7f2bef2949e41b163ab7d845908fdb9921` |
| `ubaa-p4ai-native-macos.log` | `2967ebafc7281eb213952cc4b3d61535ec25facc66c6b4be45ddf702913c769c` |
| `ubaa-p4ai-red.log` | `fca6d4787ee82fcee6d84f01949b9c1a8aa3599b5a47aff7be7b32716400a360` |
| `ubaa-p4ai-sensitive-staged.log` | `e2665752e707c6a101f23b7b6c4a4f996561be56918d5d420a7796b1736149a7` |
| `ubaa-p4ai-sensitive.log` | `e2665752e707c6a101f23b7b6c4a4f996561be56918d5d420a7796b1736149a7` |
