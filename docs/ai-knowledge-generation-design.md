# AI 知识库生成任务管理 — 技术方案

> 状态：已实施（2026-08-03 回写，含共享缓存修复）
> 关联：AI 歌单 → 歌曲知识库生成进度丢失 Bug

## 1. 问题背景

**Bug 现象**：歌曲知识库开始生成后，离开页面再回到页面，知识库进度变成 0。

**排查结论**（数据未丢失，状态丢失）：
- 知识库每批处理完成都会 `flush()` 写入 `song_knowledge.json`，磁盘数据完好
- 但进度状态（`_isGeneratingKnowledge`、`_knowledgeProgress`、`_knowledgeCached`）全部绑定在 `_SettingsAiPlaylistTabState` 局部变量上
- 离开页面 → State dispose → 状态重置；后台 async 任务继续跑，但新页面收不到进度回调（`if (mounted)` 为 false 被丢弃）
- 回到页面 → `_loadSettings` 只在 initState 时读**一次磁盘快照**，无刷新机制
  - 若读盘时机早于第一批 AI 返回 → 显示"已索引 0"
  - 即使磁盘有数据，也不会随后台任务持续更新

## 2. 任务本质

知识库生成是**小时级长任务**（数百首歌 × 每批 50 首 × 每批等 AI 10-60 秒），两个天然属性：

1. **数据已持久化**：每批完成写盘 → 天然支持断点续传 → 进程被杀代价最小
2. **状态必须跨 UI 存活**：用户必然离开页面，回来要看到真实进度

## 3. 方案对比

| 方案 | 核心 | 优点 | 致命缺点 |
|---|---|---|---|
| A. Service 单例 + ChangeNotifier | 状态放内存单例 | 改动小、解决当前 | 进程被杀状态丢失（App 常被系统回收） |
| B. 持久化进度 | 进度写磁盘 | 冷启动可恢复 | 只有"数字"，任务是否在跑仍无解 |
| C. WorkManager/后台任务 | 系统级调度 | App 被杀也继续 | 过度设计：AI 长 HTTP 在后台任务被系统限杀；复杂度高 |
| **D. 单例 + 进度持久化 + 断点续传** | 内存实时 + 磁盘兜底 | 兼顾实时性与鲁棒性 | 无（配合现有写盘机制） |

## 4. 推荐方案 D — 详细设计

**核心思想**：任务控制放内存单例（实时），进度落磁盘（跨进程），数据靠现有 JSON 天然续传。

```
AiKnowledgeService（全局单例，ChangeNotifier）
├── 实时态（内存，进程死即失效）:
│   ├── isGenerating: bool
│   ├── processed: int          // 当前任务已处理数
│   └── total: int              // 当前任务总数
├── 持久态（磁盘，冷启动恢复）:
│   ├── cachedCount: int        // 已完成索引数（song_knowledge.json）
│   ├── lastUpdate: DateTime?   // 最后更新时间（song_knowledge_meta.json）
│   └── progress.json           // 上次任务进度 {processed, total, lastUpdate}
└── 方法:
    ├── initialize()            // 懒加载：读磁盘持久态
    ├── start(List<Song>)       // 启动生成，循环批次，每批 flush + 更新状态 + notify
    ├── cancel()
    └── 复用 AiPlaylistService 的 generateKnowledge 批次逻辑
```

**UI 层**：
- `settings_ai_playlist_tab` 移除 State 进度变量，改 `ListenableBuilder` 监听单例
- 进入页面：`service.initialize()` → 从单例读所有状态渲染
- 生成期间：实时收到 notify，进度/已索引/按钮状态同步刷新

## 5. 边界场景

| 场景 | 任务 | 数据 | 用户看到 |
|---|---|---|---|
| 从未索引过（冷启动） | — | — | "已索引 0 / 总数 N"，按钮「开始生成」 |
| 生成中离开页面 | 继续跑 | 持续写盘 | 回来实时进度恢复 |
| 退后台（Android） | 继续跑 | 持续写盘 | 回前台进度已推进 |
| 退后台（iOS） | 暂停（挂起） | 安全 | 回前台恢复，进度续上 |
| 进程被杀 | 终止 | 安全（≤1 批损失） | 下次显示"已索引 X/N"，点增量更新续传 |
| 索引到一半中断 | — | JSON 完好 | "已索引 X/N"，增量更新跳过已缓存 |

**进程被杀的最大损失**：正在处理的那一批（≤50 首）的 API 调用费，数据零损坏。

## 6. 为什么不用 WorkManager

- 断点续传已把"被杀"代价降到最低，续传从断点继续
- WorkManager 适合"必须系统级保证完成"的任务；知识库生成是"尽力而为 + 可续传"
- AI 长 HTTP 连接在系统后台任务中会被限制/杀死，引入复杂度不成比例

## 7. 实施状态（2026-08-03 回写）

- ✅ 新建 `AiKnowledgeService`（ChangeNotifier 单例）— `lib/services/ai_knowledge_service.dart:18-161`
- ✅ 新增 `knowledge_progress.json` 进度持久化 — `ai_knowledge_service.dart:142-155`
- ✅ `settings_ai_playlist_tab.dart` 删 State 进度变量，改 `ListenableBuilder` 监听单例 — `lib/screens/settings_ai_playlist_tab.dart:333-335, 348, 462-478`
- ✅ 单例懒加载：首次进入设置 AI 页时 `initialize()` — `ai_knowledge_service.dart:22-23` + `settings_ai_playlist_tab.dart:43-44`
- ✅ 第 8 节进度虚增修复 — `ai_playlist_service.dart:97-103`（仅 `tags != null` 才累加 `processed`）

## 8. 附带发现（已修复）

`AiPlaylistService.generateKnowledge` 中 `_generateBatchTags` 失败（返回 null）时：

```dart
processed += batchSongs.length;   // ← 即使该批全部失败也累加（旧代码）
```

进度会虚增（显示 100% 但缓存未满）。已修复：只累加成功处理的歌曲数（`tags != null` 分支内），见 `ai_playlist_service.dart:97-103`。

## 9. 2026-08-03 补充修复：共享缓存缺失导致覆盖写（数据丢失）与计数不涨

**现象**：生成一会儿后杀进程，重进设置 AI 页显示「已索引 0」；磁盘 `song_knowledge.json` 被写成 `{}`（空）。

**根因**：

1. `AiKnowledgeService` 单例的 `_playlistService` 从未调用 `initialize()`，其 `_cache` 一直是空快照 → 每次生成把全曲库当未索引（增量/断点续传失效），且每批 `flush()` 整包覆盖写磁盘，旧数据被清空；
2. `_syncFromDisk()` 读的是单例自己那份内存 Map（初始化时快照），生成过程中「已索引 N」永不更新；
3. `File.writeAsString` 非原子写，进程被杀可能留下截断 JSON；损坏文件被静默置空。

**修复**：

- ✅ `AiPlaylistService.attachCache()` 注入共享缓存实例 — `ai_playlist_service.dart:43-49`
- ✅ `AiKnowledgeService.start()` 生成前 attach 共享实例 — `ai_knowledge_service.dart:74`
- ✅ `generateKnowledge()` 开头确保缓存已加载（防空快照覆盖写）— `ai_playlist_service.dart:60-66`
- ✅ `_syncFromDisk()` 改为读共享实例（生成方直接写同一内存，计数实时更新）— `ai_knowledge_service.dart:116-123`
- ✅ `initialize()` 生成中跳过重载（避免磁盘快照覆盖生成中内存）— `ai_knowledge_service.dart:52-58`
- ✅ 原子写（tmp + rename）+ 损坏文件备份 `.bak` — `song_knowledge_cache.dart:164-175, 178-189`

## 10. 2026-08-03 补充修复（真正的用户可见 bug）：空 Map 批次被当作成功

**现象**：重新生成时进度条持续走动、但「已索引」恒为 0、磁盘 `song_knowledge.json` 为 `{}`、导出按钮置灰。

**根因**：`_parseBatchResponse` 解析不出任何行时返回**空 Map `{}`**（非 null）；`generateKnowledge` 用 `if (tags != null)` 判断成功 → 空 Map 也通过 → `processed += 50`（进度虚增）、`saveBatchTags({})` 不写入、`flush()` 把空缓存覆盖写盘（磁盘变 `{}`）。AI 响应一旦出现格式漂移（解释文字、Markdown 代码块、中文序号 `1、`、序号后带歌名），整批解析为 0 条。

**修复**：

- ✅ 空 Map 不算成功：`tags != null && tags.isNotEmpty` 才累加并落盘，空批次跳过 — `ai_playlist_service.dart:110-135`
- ✅ 连续失败熔断：连续 3 批失败即中止，避免模型持续返回不可解析输出时白烧 token；失败原因经 `lastFailureReason` 透传 UI（SnackBar「知识库生成失败：…」），未配置 API Key 也会明确提示 — `ai_playlist_service.dart:31-39, 68-80, 98, 120-135`；`ai_knowledge_service.dart:104-109`；`settings_ai_playlist_tab.dart:462-486`
- ✅ `_parseBatchResponse` 兼容格式漂移：剔除 ``` 围栏、序号前缀正则支持 `1`/`1.`/`1、`/`[1]`/`1:`、容忍管道符前带歌名 — `ai_playlist_service.dart:178-210`
- ✅ 解析为 0 时输出完整响应诊断日志（finish_reason / content_len / reasoning_len / raw 前 600 字符）— `ai_playlist_service.dart:159-176`
- ✅ **根因修复：DeepSeek V4 思考模式**。`deepseek-v4-flash`/`deepseek-v4-pro` 默认 `thinking.type=enabled`，请求未传该参数时模型把 `max_tokens: 4000` 全部消耗在 `reasoning_content`，最终 `content` 为空 → 解析 0 条。两处请求显式加 `thinking: {'type': 'disabled'}`（仅 deepseek 模型）— `ai_playlist_service.dart:146-158`（批量标签）、`:269-283`（歌单生成）
- ✅ 歌单生成请求加 `response_format: {'type': 'json_object'}`，配合 prompt 的 JSON 指示保证输出为合法 JSON（`_parsePlaylistResponse` 已有 JSON 数组提取）— `ai_playlist_service.dart:283-285`
- ✅ 任务版本号隔离并发：cancel 后立即重新生成时，新任务递增 `_generationSerial`，旧任务在批循环开头发现 serial 变化即退出，杜绝双任务并发重复烧 API — `ai_playlist_service.dart:33-40, 72-74, 110-112`
- ✅ `AiKnowledgeService.start()` 异常兜底：`generateKnowledge` 意外异常捕获后置 `lastFailureReason` 并透传 UI，不再冒泡到异步错误 — `ai_knowledge_service.dart:90-107`
