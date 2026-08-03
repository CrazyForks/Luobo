# AI 知识库生成任务管理 — 技术方案

> 状态：设计稿（待实现）
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

## 7. 改动范围

- 新建 `AiKnowledgeService`（ChangeNotifier 单例），改造 `AiPlaylistService` 生成逻辑接入
- 新增 `progress.json` meta 持久化
- `settings_ai_playlist_tab.dart` 删 State 进度变量，改监听单例
- `main.dart` 注册单例（或懒加载）

## 8. 附带发现（可选修复）

`AiPlaylistService.generateKnowledge` 中 `_generateBatchTags` 失败（返回 null）时：
```dart
processed += batchSongs.length;   // ← 即使该批全部失败也累加
onProgress?.call(processed, total);
```
进度会虚增（显示 100% 但缓存未满）。修复：只累加成功处理的歌曲数，或在 tags 为 null 时跳过本批进度。
