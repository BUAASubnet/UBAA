# 可见无焦点窗口恢复与原生回归（P2-T）

2026-09-23，基于`94ff3a5c`的当前工作候选。范围仅宿主可见性映射及其回归；Bridge v35/schema v6、学校协议和写协调器不改。

macOS Debug真实App复现窗口hidden→inactive后读取不再推进：控制器前台标记false、调度器未运行、4项未发送任务等待、无活动RPC。冻结来源及锁定Flutter SDK逐操作核对见[source-parity的P2-T](../source-parity-offline-recovery-2026-09-17.md)。Flutter的inactive表示至少一个视图可见而没有焦点，恢复不能等待可选的resumed。

新增3项宿主行为测试，先观察隐藏/暂停后inactive不恢复订阅和读取、在途恢复未启动的实际断言失败，再将首次可见事件纳入既有恢复。随后普通焦点变化不重复认证、在途任务合并、旧密码调用仍为零。聚焦3项GREEN；完整Flutter1072项、7包静态分析、just check（含CLI端到端16项、Bridge139项）、refs/layout/sensitive通过。当前FRB生成一致性复验零漂移；公开签名和生成文件未变。

macOS、iPhone17Pro与iPadPro13M5/iOS26.5模拟器各83项原生合成矩阵通过。首次macOS83矩阵卡在测试主动进入hidden后等待下一引擎帧，精确中断，不能当通过；测试改为隐藏期间只等必要微任务，再到可见状态等待帧，原断言全部保留。该中断日志与最终GREEN均保留。

独立Release新App已通过3次WebVPN五主要来源分段读取、业务写入为零。这3次运行时Computer Use检测到锁屏，故仅为链路诊断，不计正式性能和可见验收。用户再次解锁后，独立只读进程经CUA显示首页、最小化及重新观测窗口，首页原位保留并完成更新；该操作前后恢复RPC次数8→9，完成只读调用143→260。没有将这次CUA操作的生命周期类型单独记录，因此不能称为已直接观测hidden→inactive；该映射由先前诊断和本轮三端行为回归证明。

私有真实App证据位于`p5b-process-startup-20260923/macos-p2t-release-diagnosis`，操作摘要`visible-regression-actions.json`关联原始日志hash，不提交个人内容。正式30次、全部首页来源成本分解及最终双路线继续。

以下日志位于仓库外`p2t-visible-20260923`：

| 文件 | SHA-256 |
|---|---|
| `ubaa-p2t-visible-red.log` | `65b178b59694072c3382332d9fcdfcd1d51d4a14a33e07c893799cd5ebb571e1` |
| `ubaa-p2t-visible-green-final.log` | `fd55a8865d239cb90941e705ffa9f6722353063e999fb058d1eb3f5ad787197c` |
| `ubaa-p2t-check.log` | `27594dbce8014ff9aca42f7e84eea384fde7ad0aedd581b01b467e2184fe168d` |
| `ubaa-p2t-flutter.log` | `5f681cfade05409abc78d5c0826c6f759cd07b4b26c2749c6f6a351b9bda1799` |
| `ubaa-p2t-native-macos.log` | `b5c9debd1a78cd4a7c850123be67c95fc90e29468172aadcd6cd1ac96d4c64e6` |
| `ubaa-p2t-native-macos-final.log` | `f9db653b37b785f90d544081ab6ed482c945a5dbfa0c0843b93a39ffd2aedc8e` |
| `ubaa-p2t-native-iphone.log` | `65fa4cba0b3da9d7c6f3802a6d02a705b16f6edd3db50ec50bb0f093e751ba58` |
| `ubaa-p2t-native-ipad.log` | `9ab0aecfadaa036a509dc4b0049fc40227297069ce12b448d288d021b1eab7d0` |
| `ubaa-p2t-refs.log` | `534334fd86cb3a1e18d73f92643100e7433d193d4d49b1552ec9d7a1dd5639b3` |
| `ubaa-p2t-layout.log` | `4f00b00a68dd8c9e6e16234e025883051e3585b02de206ac445d05f4d7b39498` |
| `ubaa-p2t-sensitive.log` | `ad6d7d68a3d19edd67d0f8f643a173d83bccd8e32e5a702a89d9ffd62c533bd2` |
| `ubaa-p2t-codegen-check.log` | `29063bdcf4962eb7dbf36303bd3c806720ae2c385578437c6f7eec590155f91f` |
| `ubaa-p2t-sensitive-final.log` | `c9b1dd695b5d04e7b04d17955db761cc6c19db43292895d96951e466d06a944e` |
