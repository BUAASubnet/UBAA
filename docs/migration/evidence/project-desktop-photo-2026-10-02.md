# 桌面系统选图阶段证据

日期：2026-10-02，起点`345d1236`，本提交候选。来源见[桌面选图对照](../source-parity-desktop-photo-2026-10-02.md)。

Windows/Linux使用file_selector系统单文件对话框；其它平台保留现有原生通路。照片权限仅对应用户选择文件的操作，位置/相机仍按既有Gateway实际能力处理。文件先查长度再流式限额，长度检查后增长同样拒绝超过10MiB；只交付字节、basename、MIME。取消保留空结果，重叠选择只开一个窗口，异常固定归约且不带路径。

4项行为RED先观察缺失能力返回空/不打开选择器，随后实际实现通过；专项另覆盖生产Win/Linux能力组合和文件增长限制。完整Flutter七包分析与1318项测试通过（57/98/627/339/31/91/75），完整just check、敏感检查通过，macOS Debug生产构建成功。官方SDK与OHOS锁定SDK分别解析各自宿主锁文件；曾误用官方SDK检查OHOS要求，被版本约束拒绝后改用指定fork，未修改SDK约束。

Windows/Linux插件注册文件已由Flutter更新，但本机是macOS，未宣称这两平台的原生编译或窗口已验。macOS新增插件编译通过，既有选图仍走原生MethodChannel。测试使用合成图片，真实学校上传/提交0。

## 清理

核实两个旧worktree中4个目标均非符号链接、无tracked文件、无活动进程cwd后，清理Rust target与Flutter build共49567844KiB（约47.27GiB）。保留原worktree、未提交代码/文档、冻结引用、私有会话与外部媒体。此次只清理可再生成产物，记录在私有cleanup.json。

## 当前日志

根目录：`/Users/moorefoss/Library/Application Support/UBAA-private-evidence/project-review-20261002-resume`。

| 文件 | SHA-256 |
|---|---|
| `photo-behavior-red.log` | `01a2210ceed2d40279ba7385baeb3a63adcd0ec88f12cfb1d05927f3bc94d6c9` |
| `photo-green2.log` | `1f7c79822ea0a60fd9b68ec5b9e50d4ef8addb379ada6456f30022397a4a946c` |
| `photo-flutter3.log` | `ddf1279443f36866ac55187a3cc469193945b40bc5130957533f775b74e7b281` |
| `photo-check.log` | `795b54cda7829160e5644968c3c255e43cf0bfc47c967470aaab33c1929eb3bd` |
| `photo-sensitive.log` | `818e25e27849775d8eafe33fa3ef3c74b49362dac35db3b24827bc046b4975a7` |
| `photo-ohos-pubget.log` | `f0310363687e3842a916af757e522869c659f098b869f535a1dd52a96ca53d48` |
| `final-macos-build.log` | `086f6a4094bf951fcfdc202fed4c175a65d5e333fcdb37ac4457fd00d7e02daa` |
| `cleanup.json` | `931215f09461ed1f98d0f35b99f26dbb0ecce828b8b6e2cd995444040f1d1f66` |
