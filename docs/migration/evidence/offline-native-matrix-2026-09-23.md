# 原生脱敏异常与交互矩阵

日期：2026-09-23。入口`apps/ubaa_flutter/integration_test/offline/acceptance_matrix_test.dart`，使用当前生产组件、脱敏后端，以及独立合成FFI缓存和系统材料；不读取真实账号、不提交学校业务。此证据不等于Core-live、真实账号App或实体手机/平板性能。

macOS、iPhone 17 Pro/iOS26.5模拟器、iPad Pro 13 M5/iOS26.5模拟器各80项通过。涵盖缓存首页与原位恢复、autoLogin/所需路线边界、长读取调度/部分范围保留、前后台/网络提示/迟到结果、清理与重建、未知写结果本机核对、跨日展示、放大文字和图书馆查询草稿/返回位置。学校操作仍为脱敏测试，原生网络接口只枚举，不输出地址，不当作学校可达。

希冀同ID变化、历史课新增、无序/长周期/未知日期及分页一致性由当前Core确定性门禁补充；不能把这80项称为每种算法都经真实上游验证。双路线真实账号链路与三端30次性能继续单列。

首次macOS矩阵77项通过、3项固定日期断言失败：原生帧未继承mount的局部withClock。首页新增可选Clock依赖，测试显式传入同一个固定时钟，生产默认行为不变，未删除或弱化断言；三端重跑全部通过。修改后完整Flutter1069项/7包分析和集成入口分析通过。

日志位于仓库外`p5-native-matrix-20260923`：

| 文件 | SHA-256 |
|---|---|
| `ubaa-p5-matrix-macos.log` | `e084f330b52d7bc60fed99d5de0f0195a153d27003abc9943245f5c5e7af70a2` |
| `ubaa-p5-matrix-macos-green.log` | `50d8d98c864a58d325cf4cfa2d5c036ef5fe2847ac5851fd966efecdd6b33efd` |
| `ubaa-p5-matrix-iphone.log` | `e7afe2b5243f037c18b1a73e8df20e7745a83cf285c24b53df4afd7f000e431c` |
| `ubaa-p5-matrix-ipad.log` | `8e9fb371c79db93871b31196ce65010a0e5ba8c7c4e0f06af5038c3325332af3` |
| `ubaa-p5-matrix-flutter.log` | `db6fdf52f8826a6cff159e09d965e75d9f71c3ec49cfb2e79e6e8bad609ef11a` |
| `ubaa-p5-integration-analyze.log` | `df6df22f956c2011ee90868531b8be155230bafd4fc0c0336d8d6606f4c8eb7a` |

## P2-T最终候选重跑

新增可见无焦点恢复3项后，macOS、iPhone/iPad模拟器各83项通过，完整Flutter1072项/7包分析通过。首次macOS隐藏期间等待帧导致测试驱动停滞，修正等待方式后全量重跑，断言未弱化；本轮日志hash与真实App证据见[P2-T](offline-visible-resume-2026-09-23.md)。上面的80项是先前同阶段记录，不冒充包含新增行为。


## P4-AH当前候选

P2-U新增9项成绩调度、P4-AH新增8项基线与清理边界后，三端最终各100项通过。已有单项FFI内另覆盖v36成绩基线保存、密文重开、路线/学期隔离、跨句柄退出拒绝；macOS成绩旧交互另12项通过。日志和hash见[P4-AH证据](offline-grade-baseline-2026-09-23.md)。
