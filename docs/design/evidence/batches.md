# 历史 UI 验收批次索引

这些批次记录历史采集，不代表当前候选已通过设备或真实业务验收。截图与录屏仍位于仓库外；逻辑路径、摘要和提交映射按 [证据规则](README.md) 保留。

默认 `rg` 检索跳过历史 JSON 与 SHA256SUMS；使用显式文件路径或 `rg --no-ignore` 仍可查询。元数据字节未移动、重写或删除。

| 批次 | 跟踪文件 | JSON 元数据 | 总字节 |
|---|---:|---:|---:|
| [old-d1-native](ui-ux/old-d1-native/) | 95 | 94 | 61874 |
| [old-d1b-native](ui-ux/old-d1b-native/) | 121 | 119 | 79008 |
| [old-d1c-native](ui-ux/old-d1c-native/) | 35 | 34 | 22591 |
| [old-d2-native](ui-ux/old-d2-native/) | 92 | 91 | 60418 |
| [old-d2b-native](ui-ux/old-d2b-native/) | 92 | 91 | 61092 |
| [old-d3-native](ui-ux/old-d3-native/) | 198 | 197 | 135143 |
| [old-d4-native](ui-ux/old-d4-native/) | 168 | 167 | 113160 |
| [old-d5-native](ui-ux/old-d5-native/) | 114 | 113 | 78043 |
| [old-e1-native](ui-ux/old-e1-native/) | 126 | 125 | 83575 |
| [old-e2a-native](ui-ux/old-e2a-native/) | 106 | 105 | 76648 |
| [old-e2b-native](ui-ux/old-e2b-native/) | 70 | 69 | 48878 |
| [old-e3a-native](ui-ux/old-e3a-native/) | 68 | 67 | 43515 |
| [old-e3b-native](ui-ux/old-e3b-native/) | 87 | 86 | 56953 |
| [old-e3c-native](ui-ux/old-e3c-native/) | 135 | 133 | 90394 |
| [old-e4-native](ui-ux/old-e4-native/) | 104 | 103 | 86002 |
| [old-e5-native](ui-ux/old-e5-native/) | 63 | 61 | 45033 |
| [old-e6-native](ui-ux/old-e6-native/) | 31 | 29 | 26379 |
| [old-o2-native](ui-ux/old-o2-native/) | 116 | 114 | 84304 |
| [old-o3a-native](ui-ux/old-o3a-native/) | 262 | 259 | 243957 |
| [old-o3b-native](ui-ux/old-o3b-native/) | 272 | 268 | 256607 |
| [old-o3c-native](ui-ux/old-o3c-native/) | 89 | 87 | 66766 |
| [old-p5a-native](ui-ux/old-p5a-native/) | 97 | 95 | 59525 |
| [old-p5b-native](ui-ux/old-p5b-native/) | 137 | 135 | 93078 |
| [old-p5b2-native](ui-ux/old-p5b2-native/) | 140 | 138 | 94559 |
| [old-p5c-native](ui-ux/old-p5c-native/) | 149 | 147 | 101203 |
| [old-p5d-native](ui-ux/old-p5d-native/) | 281 | 279 | 192258 |
| [old-p5e-native](ui-ux/old-p5e-native/) | 25 | 22 | 30406 |
| [old-p5f-native](ui-ux/old-p5f-native/) | 25 | 24 | 20614 |
| [p3-native](ui-ux/p3-native/) | 74 | 74 | 51556 |
| [p3a-native](ui-ux/p3a-native/) | 78 | 78 | 57439 |
| [p3b-native](ui-ux/p3b-native/) | 23 | 23 | 29480 |
| [p4a-native](ui-ux/p4a-native/) | 89 | 84 | 60435 |
| [p4b-native](ui-ux/p4b-native/) | 220 | 220 | 268075 |
| [p4b2-native](ui-ux/p4b2-native/) | 236 | 234 | 280582 |

合计 34 个批次。外部截图归档与原提交映射仍以 [external-archive.json](ui-ux/external-archive.json) 为准。

本索引只汇总版本控制中的历史材料；应用资源和 golden 基准继续留在各自工程目录。
