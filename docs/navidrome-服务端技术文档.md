# Navidrome 服务端技术文档（源码解析 + Luobo 客户端对接）

> 状态：源码研究完成（2026-08-03）
> 范围：Navidrome 服务端整体架构、Subsonic/OpenSubsonic API 实现、数据模型、媒体扫描、转码、歌词、播放统计，以及与 Luobo（Musly）客户端的对接要点
> 源码版本：commit `279ff98`（2026-08-02，master 分支），API 版本 `1.16.1`，OpenSubsonic 支持

## 1. 项目概述

Navidrome 是一个用 **Go** 编写的开源自托管音乐服务器（GitHub: navidrome/navidrome，GPL-3.0），部署在 NAS / Docker 上，作为"个人音乐库服务端"。它兼容 **Subsonic API**（含 OpenSubsonic 扩展），因此任意支持 Subsonic 协议的客户端（DSub、Symfonium、SubMusic、以及我们的 Luobo/Musly）都可以直接连接使用。

核心特性：

- 多用户、多音乐库（Library）、多播放器（Player）管理；
- 媒体库增量扫描（文件系统监听 + 定时扫描），自动发现移动/重命名文件；
- 服务端转码（ffmpeg）与直传（DirectPlay）双模式流媒体；
- 封面图按需生成缩略图并做磁盘缓存；
- 歌词多格式解析（LRC/SRT/TTML/嵌入标签/外部文件）+ 外部 Provider（LRCLIB 等）；
- 智能播放列表（规则 DSL → SQL）；
- 播放历史记录与 Last.fm / ListenBrainz 双写上报（带缓冲重试）；
- 可选 Jellyfin API 兼容层、Jukebox（mpv 本地播放）等。

### 1.1 技术栈

| 组件 | 选型 | 说明 |
|---|---|---|
| 语言 | Go | 单二进制，交叉编译方便 |
| HTTP 路由 | `github.com/go-chi/chi` | 手写路由表，无反射 |
| 依赖注入 | `google/wire` | 编译期生成 `wire_gen.go` |
| 数据库 | SQLite（`mattn/go-sqlite3`） | WAL 模式，DSN 参数配置 |
| 数据库迁移 | `pressly/goose` v3 | `db/migrations/` 约 120 个迁移文件 |
| 元数据读取 | go-taglib（WASM 版 TagLib） | `adapters/gotaglib/`，纯 Go 不依赖 CGO |
| 转码 | ffmpeg / ffprobe | 外部进程，流式管道输出 |
| 文件监听 | `rjeczalik/notify` | 跨平台 inotify/kqueue/ReadDirectoryChangesW |
| 搜索 | SQLite FTS5 + bm25 | CJK 查询自动回退 LIKE |
| 前端 | React（`ui/` 目录） | Web UI，独立构建 |

### 1.2 顶层目录结构

```
main.go                 入口（引用 build tags: NETGO, SQLITE_FTS5）
cmd/                    cobra 命令入口（server/scan/backup/user/pls/plugin…）+ wire 注入
server/                 HTTP 层：subsonic(API)、nativeapi(REST)、public(分享)、jellyfin、auth、events
core/                   业务核心：auth、artwork、stream、scrobbler、playback、lyrics、agents、ffmpeg、share
model/                  领域模型 + criteria(智能歌单 DSL) + metadata(元数据归一化) + lyrics 解析器
persistence/           repository 模式：SQL 查询、annotation、FTS 搜索、smart playlist SQL 生成
scanner/                媒体库扫描（4 阶段流水线）+ 文件监听 watcher
db/                     SQLite 初始化 + goose migrations + backup/optimize
scheduler/              定时任务调度（cron 表达式）
conf/                   配置系统（viper，环境变量/配置文件）
adapters/               lastfm、listenbrainz、gotaglib 等外部服务适配器
plugins/                插件管理器（Go 插件体系）
ui/                     React Web UI
```

## 2. 整体架构与启动流程

### 2.1 启动流程

`main.go` → `cmd.Execute()`（`cmd/root.go`）→ `runNavidrome()` 用 `errgroup` 并行启动 11 个 goroutine（`cmd/root.go:79-102`）：

```go
g.Go(startServer(ctx))            // HTTP 服务
g.Go(startSignaller(ctx))
g.Go(startScheduler(ctx))         // cron 调度器
g.Go(startPlaybackServer(ctx))    // Jukebox（可选）
g.Go(schedulePeriodicBackup(ctx)) // 定时备份（Backup.Schedule 配置）
g.Go(startInsightsCollector(ctx)) // 遥测收集（可选）
g.Go(scheduleDBAnalyzer(ctx))     // 定期 SQLite ANALYZE
g.Go(startPluginManager(ctx))
g.Go(runInitialScan(ctx))         // 启动扫描（延迟 2s）
if conf.Server.Scanner.Enabled {
    g.Go(startScanWatcher(ctx))       // 文件系统监听
    g.Go(schedulePeriodicScan(ctx))   // 定时扫描（Scanner.Schedule cron）
}
```

### 2.2 依赖注入（wire）

`cmd/wire_injectors.go` 用 `wire.Build(allProviders)` 声明全部 provider，编译期生成 `cmd/wire_gen.go`。关键绑定：

- 接口绑定：`agents.PluginLoader → *plugins.Manager`、`scanner.Scanner → *scanner.ScannerImpl` 等；
- `CreateSubsonicAPIRouter` 按依赖图实例化：`db.Db() → persistence.New → artwork.GetImageCache → ffmpeg.New → events.GetBroker → stream.NewMediaStreamer → subsonic.New(...)`（16 个参数，`wire_gen.go:90-118`）。

> 注意：插件管理器拿到后还会**回填 Subsonic router**（`GetPluginManager`，`wire_injectors.go:145-149`），允许插件注册自定义 Subsonic 端点。

### 2.3 HTTP 服务（server/server.go）

- `New()`：`initialSetup`（首次建库/创建 admin）、`auth.Init`（JWT 密钥）、`initRoutes`、`mountAuthenticationRoutes`、`checkFFmpegInstallation`；
- `initRoutes`（`server.go:167-203`）默认中间件链：`secureMiddleware → corsHandler → RequestID → realIP → Recoverer → Heartbeat(/ping) → robotsTXT → serverAddress → clientUniqueID → compress → loggerInjector → JWTVerifier`；
- 支持 TCP / Unix socket / 可选 TLS；优雅关闭 3 秒超时。

## 3. 四大 API 面

| 路由 | 包 | 作用 |
|---|---|---|
| `/rest` | `server/subsonic/` | Subsonic/OpenSubsonic 协议 API，**Luobo 客户端走这里** |
| `/api` | `server/nativeapi/` | Navidrome 自有 REST API（Web UI 用），基于 `deluan/rest` 通用 CRUD |
| `/share` | `server/public/` | 公开分享链接（封面 `/img/{id}`、流 `/s/{id}`、下载 `/d/{id}`、m3u、分享页） |
| `/jellyfin` | `server/jellyfin/` | 可选 Jellyfin 兼容层（`Jellyfin.Enabled`，默认关闭） |
| `/auth` | `server/auth.go` | `POST /auth/login`（IP 限流 5 次/20s）、`POST /auth/createAdmin` |
| `/api/events` | `server/events/` | SSE 事件推送（需 Authenticator + JWTRefresher） |

## 4. 认证机制（客户端对接核心）

### 4.1 Subsonic 参数认证（server/subsonic/middlewares.go）

请求中间件链：`checkRequiredParameters`（校验 `u/v/c`）→ `authenticate` → `UpdateLastAccessMiddleware` → `getPlayer`（`api.go:101-108`）。

`authenticate` 从 query 取 `u/p/t/s/jwt`，调 `validateCredentials`（`middlewares.go:175-198`），**支持三种方式**：

```go
switch {
case jwt != "":                          // 方式1：JWT（UI 登录后可用）
    claims, err := auth.Validate(jwt)
    valid = err == nil && claims.Subject == user.UserName
case pass != "":                         // 方式2：明文密码 p=
    if strings.HasPrefix(pass, "enc:") { // 兼容 enc:hex 编码
        pass = hex.DecodeString(pass[4:])
    }
    valid = pass == user.Password
case token != "":                        // 方式3：token+salt（推荐）
    t := fmt.Sprintf("%x", md5.Sum([]byte(user.Password+salt)))
    valid = t == token
}
```

**与 Luobo 客户端的对应关系**：客户端 `subsonic_service.dart` 的 `_getAuthParams()` 生成 `t = md5(password + salt)`（salt 随机 8 位），与服务端算法完全一致；`useLegacyAuth` 开关对应 `p=` 明文方式。DB 中用户密码是 AES 加密存储（`persistence/user_repository.go` 的 `decryptPassword`），验证时先解密再比较。

### 4.2 JWT（core/auth/auth.go）

- 两套 HS256 JWT：`TokenAuth`（UI/API 会话）与 `PublicTokenAuth`（公开分享链接），密钥加密存在 DB Property；
- `CreateToken` 签发，`TouchToken` 滑动续期（过期时间 = now + `SessionTimeout`，默认 **48h**）；
- 传递方式：`X-ND-Authorization: Bearer <token>` 头 / Cookie / URL query（`server/auth.go:173-184`）；
- `/auth/login` 返回 `token` + `subsonicSalt/subsonicToken`（同一算法），UI 拿到的凭据可直接用于 Subsonic API。

## 5. Subsonic API 端点详解

### 5.1 响应格式（server/subsonic/helpers.go + responses/）

每个响应 `newResponse()` 固定带：

```xml
<subsonic-response status="ok" version="1.16.1" type="navidrome"
    serverVersion="vX.Y.Z" openSubsonic="true">
```

- `f` 参数决定 `json` / `jsonp` / 默认 `xml`（`api.go:344-410`）；
- 错误码枚举在 `responses/`（如 `ErrorMissingParameter`、`ErrorDataNotFound`、`ErrorAuthorizationFail`、429 `ErrorTooManyTranscodes` 带 `Retry-After: 5`）；
- 每个端点同时注册 `/endpoint` 与 `/endpoint.view`（`addHandler`，`api.go:293-296`）；
- **`type="navidrome"` 就是 Luobo 客户端 `pingWithError` 探测 `serverType` 的数据来源**（`subsonic_service.dart:409-422` 直接透传 `response['type']`）。

### 5.2 端点分组（api.go 路由表）

| 分组 | 端点 | 说明 |
|---|---|---|
| system | `ping` | 健康检查/认证验证 |
| browsing | `getMusicFolders` `getIndexes` `getArtists` `getArtist` `getAlbum` `getSong` `getGenres` `getAlbumInfo` `getArtistInfo` `getTopSongs` | 浏览库 |
| albumLists | `getAlbumList(2)` `getStarred(2)` `getRandomSongs` `getSongsByGenre` `getNowPlaying` | 专辑列表/随机/正在播放 |
| mediaAnnotation | `setRating` `star` `unstar` `scrobble` `reportPlayback` | 收藏/评分/播放上报 |
| playlists | `getPlaylists` `getPlaylist` `createPlaylist` `updatePlaylist` `deletePlaylist` | 歌单 |
| bookmarks | `getBookmarks` `createBookmark` `deleteBookmark` `getPlayQueue` `savePlayQueue`（OpenSubsonic indexBasedQueue） | 书签/播放队列 |
| searching | `search2` `search3` | 综合搜索 |
| mediaRetrieval | `stream` `download` `getLyrics` `getLyricsBySongId` | 媒体/歌词 |
| artwork | `getCoverArt` | 封面（带 ThrottleBacklog 限流） |
| radio | `getInternetRadioStations` 增删改（adminOnly） | 网络电台 |
| sharing | `getShares` `createShare` `updateShare` `deleteShare` | 分享 |
| jukebox | `jukeboxControl` | 服务端播放（默认 501，需启用） |
| 未实现 | 注册 `h501`（getPodcasts、createUser…） | 明确不支持 |
| 废弃 | 注册 `h410`（search、getChatMessages、getVideos…） | 返回 410 |

### 5.3 关键端点实现

**stream（server/subsonic/stream.go:20-54）**

```go
mf, _ := api.ds.MediaFile(ctx).Get(id)          // 1. 按 ID 定位文件
streamReq := api.transcodeDecision.ResolveRequest(ctx, mf, format, maxBitRate, timeOffset)
stream, _ := api.streamer.NewStream(ctx, mf, streamReq)
stream.Serve(ctx, w, r)                          // 3. 写响应（含 Range）
```

- `format=="raw"` 直接原样；否则 `legacy_client.go` 构造客户端能力 → `decider.MakeDecision`（见 §6）；
- 直传（可 seek）→ `http.ServeContent` 自动处理 Range；转码流 → 写 `Accept-Ranges: none`（**转码流不可拖动 seek**，Luobo 注释 #170 与此对应）；
- `estimateContentLength=true`（OpenSubsonic 扩展）：`EstimatedContentLength = duration × bitrate / 8 × 1024`（`media_streamer.go:149-151`），让转码流也能估计时长/拖动 —— **Luobo 客户端固定附加此参数**；
- `timeOffset`（OpenSubsonic transcodeOffset）→ ffmpeg `-ss` 输入级 seek。

**getCoverArt（server/subsonic/media_retrieval.go:55-91）**

```go
id, size, square := p.String("id"), p.IntOr("size", 0), p.BoolOr("square", false)
imgReader, lastUpdate, _ := api.artwork.GetOrPlaceholder(ctx, id, size, square)
w.Header().Set("cache-control", "public, max-age=315360000")   // 10 年强缓存
w.Header().Set("last-modified", lastUpdate.Format(http.TimeFormat))
```

- 找不到封面时返回内嵌占位图（`consts.PlaceholderArtistArt/PlaceholderAlbumArt`）；
- `size>0 || square` → 原图缩放（CatmullRom）→ 编码（WebP/JPEG/PNG）→ **FileCache 磁盘缓存**（`cache/images/`，默认 100MB）；
- 缓存键 = `原图Key.size[.square][.quality]`（`reader_resized.go:69-75`）—— **同一封面固定 size 才能命中缓存**，这正是 Luobo 客户端统一 `size=600` + 固定 salt 的原因；
- ID 兼容：裸实体 ID 也能用（`getArtworkId` 先解析 ArtworkID，失败则查实体取 `CoverArtID`）。

**scrobble / reportPlayback（server/subsonic/media_annotation.go:164-296）**

- `scrobble?submission=true` → 记录播放 + 上报外部 scrobbler；`submission=false` → 更新 now playing；
- `reportPlayback`（OpenSubsonic playbackReport）支持 `state=starting/playing/paused/stopped`、`positionMs`、`playbackRate`；
- 内部 `core/scrobbler/play_tracker.go`：以 `clientId` 为 key 维护 `PlaybackSession`（TTL = 剩余时长 + 5s）；`stopped` 且播放超过 `min(时长×50%, 240s)` 才算一次播放（`incPlay`：media/album/artist 计数 +1）；
- 外部上报走 **buffered scrobbler**（`scrobble_buffer` 表 + 指数退避 5s→4min 重试），Last.fm 错误码 11/16 重试、其余丢弃（`adapters/lastfm/agent.go`）。

**star/unstar/setRating（media_annotation.go:20-162）**

- 参数合并 `id/albumId/artistId`，按实体类型分派 repository；
- 存储：`annotation` 表，`(item_id, item_type, user_id)` 唯一，`LEFT JOIN + coalesce` 注入查询（`persistence/sql_annotations.go`）；
- `setRating` 会重算基表 `average_rating`（`updateAvgRating`）；
- 变更后 broker 广播 `RefreshResource` 事件（Web UI 实时刷新）。

**getAlbumList2（server/subsonic/album_lists.go:19-118）type 映射**

| type | 排序 | 过滤 |
|---|---|---|
| `newest` | `recently_added desc` | — |
| `recent` | `playDate desc` | `play_date > 0` |
| `random` | `random`（`SEEDEDRAND` 函数） | — |
| `alphabeticalByName` | `name` | — |
| `alphabeticalByArtist` | `artist` | — |
| `frequent` | `playCount desc` | `play_count > 0` |
| `starred` | `starred_at desc` | `starred = true` |
| `highest` | `rating desc` | `rating > 0` |
| `byGenre` | `name` | `json_tree(tags,'$.genre')` EXISTS |
| `byYear` | `max_year` | `min_year/max_year` 区间 |

- 统一 `ApplyLibraryFilter`（多库过滤）+ `size` 截断到 500；响应带 `x-total-count` 头。

**search3（server/subsonic/searching.go + persistence/sql_search*.go）**

- 查询预处理：小写 + 去重音（`sanitize.Accents`）+ 去尾部 `*`；
- 策略（`sql_search.go:40-48`）：**含 CJK → LIKE**（FTS5 unicode61 对无空格分词效果差）；否则 **FTS5 + bm25**（`<table>_fts` 虚拟表，列权重如 title×10/album×5/artist×3，`bm25(fts, 权重)` 排序）；
- 两阶段查询（`executeTwoPhase`）：Phase 1 只取 rowid（覆盖索引 + LIMIT/OFFSET），Phase 2 `row_number() OVER ()` hydrate 全列；
- 空查询返回全部（自然序）、合法 UUID 按 MBID 匹配、`len(q)<2` 无结果。

**歌词（server/subsonic/media_retrieval.go:93-144 + model/lyrics_*.go）**

- `getLyrics(artist,title)` → 纯文本（兼容旧客户端）；`getLyricsBySongId(id)` → OpenSubsonic `structuredLyrics`（`{displayArtist, displayTitle, lang, synced, line:[{start,value}], cueLine}`）；
- 解析器：LRC（含 Enhanced LRC 词级 cue）、SRT、TTML（1297 行，含 frameRate/tickRate 单位）、lyricsfile（YAML 多声部）、嵌入 ID3 USLT/SYLT（`gotaglib.go:192-217` 提取 `lyrics:<lang>`）；
- 回退链：`conf.Server.LyricsPriority` 配置（`embedded → .sidecar 文件 → 插件/LRCLIB`），`core/lyrics/` 负责编排。

## 6. 流媒体与转码

### 6.1 转码决策（core/stream/decider.go:40-120）

`MakeDecision` 流程：

1. ffprobe 探测源流（结果缓存到 `mf.ProbeData`）；
2. 客户端最大码率限制（`MaxAudioBitrate > 0 && src.Bitrate > Max`）→ 跳过 DirectPlay；
3. **DirectPlay 判定**：遍历 `DirectPlayProfiles`，核对 protocol(仅 http)/container/codec/channels/CodecProfiles，命中直接原文件直传；
4. 否则遍历 `TranscodingProfiles` → `computeTranscodedStream`：解析目标格式（mp4+aac→aac）、`LookupTranscodeCommand`（DB 自定义命令优先，回退 `consts.DefaultTranscodings` 内建：mp3 192k/opus 128k/aac 256k/flac）、拒绝 lossy→lossless、按 codec 硬限 clamp 采样率/声道/码率；
5. 全不满足 → 报错 `no compatible playback profile found`。

### 6.2 ffmpeg 执行（core/ffmpeg/ffmpeg.go）

- 默认命令走 `buildDynamicArgs`（`-ss <offset> -i <path> -map 0:a:0 -c:a <codec> [-b:a <N>k] -v 0 -f <fmt> -`，`-ss` 放在 `-i` 前做输入级快速 seek）；
- 自定义命令走模板（占位符 `%s`=路径、`%t`=offset、`%b`=码率）；
- stdout 接 `io.Pipe` 流式输出，stderr 用 4KB limitedWriter 防内存膨胀。

### 6.3 转码缓存与限流

- **转码缓存**：`TranscodingCache`（`cache/transcoding/`，默认 100MB），键 = `mf.ID.UpdatedAt.bitRate.sampleRate.bitDepth.channels.format.offset`（`media_streamer.go:59-61`）—— 文件变化（UpdatedAt）或转码参数变化都会导致缓存失效重转；
- **限流**：`TranscodeLimiter`（`core/stream/limiter.go`）全局 + 每用户双配额（`Transcoding.MaxConcurrent` / `MaxConcurrentPerUser`），满 → HTTP **429 + `Retry-After: 5`**（错误码 `ErrorTooManyTranscodes`）。

## 7. 数据模型与持久化

### 7.1 SQLite（db/db.go）

- DSN（`consts.go:14`）：`navidrome.db?cache=shared&_busy_timeout=15000&_journal_mode=WAL&_foreign_keys=on&synchronous=normal`；
- 最大连接数 `max(4, NumCPU)`；
- 迁移：goose v3，`db/migrations/` 下 `时间戳_描述.go/.sql`（约 120 个，如 `20260220173400_add_fts5_search.go`），`.go` 迁移用 `init()+goose.AddMigrationContext` 注册；迁移提示工具 `forceFullRescan`（写 `FullScanAfterMigration` property 触发全量重扫）；
- 备份：`db.Backup`（SQLite backup API）+ `Prune`（按 `Backup.Count` 清理旧备份）。

### 7.2 核心表与关系

| 表 | 说明 |
|---|---|
| `media_file` | 歌曲：title/album/album_id/duration/bit_rate/play_count/mbz_* 元数据 + `tags`(JSON) + `lyrics`(JSON) + `probe_data` + `library_id` |
| `album` / `artist` | 专辑/艺人，含 `average_rating`、`play_count`、`stats`(JSON) |
| `media_file_artists` | **participants 多艺人**：`(media_file_id, artist_id, role)`，支持主艺人/制作人/工程师等角色（TIPL 解析） |
| `annotation` | 用户级收藏/评分：`(item_id, item_type, user_id, starred, starred_at, rating, rated_at, play_date)` |
| `playlist` / `playlist_tracks` | 歌单 + 曲目（含智能歌单 `rules`/`evaluated_at`） |
| `scrobble` / `scrobble_buffer` | 播放历史（`EnableScrobbleHistory` 时）/ 外部上报缓冲 |
| `folder` | 目录 + 内容 hash（增量扫描依据） |
| `library` | 多音乐库（`name/path/type`，path 支持 URL scheme，如 `rock:///music`） |
| `tag` / `library_artist` | 自定义标签映射 / 库-艺人关联（隔离多库艺人） |
| `property` | KV 配置（JWT 密钥、迁移标记等） |

repository 模式：`persistence/` 每个实体一个 repository，统一实现 `model.DataStore` 接口（`WithTx` 事务）、`GetAll/CountAll/Get/Exists` 等通用方法（`sql_base_repository.go`），并按用户注入 annotation JOIN 与 library 过滤。

## 8. 媒体库扫描（scanner/）

### 8.1 四阶段流水线（scanner/scanner.go:137-163）

用 `go-pipeline` 流水线库，`Phase1→Phase2→(Phase3∥Phase4)→GC→统计`：

| 阶段 | 文件 | 职责 |
|---|---|---|
| Phase 1 folders | `phase_1_folders.go` | 遍历目录树，按 `folder` 内容 hash 判断过期；对比 DB 已有 tracks，按 modtime 导入新/变更文件；`gotaglib` 读标签（批量 200）→ `metadata.ToMediaFile` → 分组建 album/artist（merge participants）→ 单事务持久化 → 预缓存封面 |
| Phase 2 missing tracks | `phase_2_missing_tracks.go` | 处理移动/重命名：PID（persistent ID）配对，三层匹配 `Equals(精确) → 唯一配对 → IsEquivalent(仅比较 basename)`；跨库移动按 MBZ ID/内在属性检测；`moveMatched` 保留 ID 与注释；按 `PurgeMissing`（never/always/full）清理 |
| Phase 3 refresh albums | `phase_3_refresh_albums.go` | 刷新 touched albums：`ToAlbum()` 重建并与 DB `Equals` 比较，无变化跳过；结束刷新播放计数 |
| Phase 4 playlists | `phase_4_playlists.go` | 导入 `.m3u/.m3u8/.nsp` 播放列表（`AutoImportPlaylists` 开启时；无 admin 用户则延迟到 admin 创建后） |
| 收尾 | `runGC` | 清理孤儿 annotation、空专辑、空艺人；刷新统计 |

### 8.2 元数据提取

- 默认提取器 **`taglib`**（`adapters/gotaglib/`，WASM 版 TagLib，纯 Go）；旧 ffmpeg 提取器（`scanner/metadata_old/`）已废弃；
- `model/metadata/metadata.go`：`clean()` 按 `TagMappings()` 归一化（别名/分隔/清洗）→ `map_mediafile.go` 映射为 MediaFile（ReplayGain、PID、AlbumID、音频属性、歌词 `mapLyrics`）→ `map_participants.go` 构建 Participants；
- 支持格式：任何 MIME `audio/*`（mp3/flac/ogg/opus/m4a/wma/wav/aiff/ape/wv/dsf…）、封面任意 `image/*`、播放列表 `.m3u/.m3u8/.nsp`（`model/file_types.go`）。

### 8.3 文件监听（scanner/watcher.go）

- 基于 `rjeczalik/notify`（非 fsnotify），递归监听，事件去重 + **防抖**（`Scanner.WatcherWait`，默认 5s）；
- 变化 → 累积 `ScanTarget{libraryID, folderPath}` → 增量扫描（`DevSelectiveWatcher` 开启时按目录，否则 quick scan）；扫描中则 3 倍等待重试；
- `.ndignore` 过滤（类似 .gitignore），跳过隐藏/系统路径。

### 8.4 多音乐库

- `scanState.libraries` 逐库扫描，每库独立 FS（`storage.For(lib.Path)`）；
- `library_id` 贯穿 media_file/album/folder；`library_artist` 关联表隔离艺人（同一艺人在两个库是两条关联）；单库 FS 错误不影响其他库。

## 9. 播放统计、Scrobble 与 Now Playing

- **状态维护**：`core/scrobbler/play_tracker.go` 的 `playMap`（`SimpleCache[string, PlaybackSession]`），以 `clientId` 为 key，TTL 过期；
- `ReportPlayback`：`starting` → 建会话；`playing/paused` → 更新 position/rate（playing TTL = 剩余时长+5s，paused = 30min）；`stopped` → 达阈值记播放 + 上报，移除会话；
- `GetNowPlaying`：返回 `playMap` 全部会话，playing 状态用 `PositionMs + elapsed×PlaybackRate` 外推位置并 clamp 到时长；
- **Jukebox**（`core/playback/`，默认关闭）：mpv 播放器做服务端出声，`jukeboxControl` 控制。

## 10. 智能播放列表（model/criteria/ + persistence/criteria_sql.go）

- **DSL**：顶层 `all`/`any` 组合（JSON），20+ 操作符（`Is/IsNot/Gt/Lt/Contains/StartsWith/InTheRange/InTheLast/InPlaylist/IsMissing` 等），字段注册表 `fieldMap`（title/year/playcount/rating/loved/duration/bpm/mbz_* + annotation 字段 + 自定义 tag/角色）；
- **SQL 翻译**：`smartPlaylistCriteria.Where()` 用 `squirrel` 生成；tag 条件 → `exists(select 1 from json_tree(media_file.tags,'$.<tag>') ...)`；角色 → `exists(select ... from media_file_artists mfa join artist ...)`；annotation 列处理 NULL 语义（`COALESCE(col, default)`）；同字段条件合并成单 EXISTS（批量 350 防 SQLite 表达式深度超限）；
- **刷新**：`refreshSmartPlaylist` 删旧重建 `playlist_tracks`（`row_number() over (order by ...) as id`），按 `evaluated_at` + `RefreshDelay()` 判断是否到期；引用子智能歌单（`inPlaylist`）先级联刷新。

## 11. 搜索实现

见 §5.3 search3。补充：`persistence/sql_search.go` 的 `doSearch` 优先级 = **空查询(全量) → UUID(MBID) → len<2(空结果) → 策略搜索**；`getSearchStrategy` = `legacy(LIKE full_text)` / `CJK(LIKE 核心列)` / `FTS5(bm25)`；FTS 查询构建保留引号短语、`*` 前缀通配、处理 `a-ha`/`R.E.M.` 等标点词，每个 token 包装 `(t OR t*)` 让精确命中排前。

## 12. 调度器与维护任务（scheduler/ + cmd/root.go）

| 任务 | 调度方式 | 说明 |
|---|---|---|
| 周期扫描 | `Scanner.Schedule`（cron，默认 `"0"` 禁用） | 定时全量扫描 |
| 定时备份 | `Backup.Schedule`（cron，默认空=禁用） | `db.Backup` + `db.Prune`（按 `Backup.Count`） |
| DB 分析 | `EnableScheduledDBAnalyze`（默认开，`DBAnalyzeCheckSchedule`） | 有 schema 变更/碎片时 `db.OptimizeIfNeeded`（ANALYZE），扫描进行中跳过 |
| 维护 | 扫描收尾 | `core/maintenance.go`：`DeleteMissingFiles`/`DeleteAllMissingFiles`（删除 missing 文件并刷新受影响专辑） |

`scheduler.GetInstance().Add(cronExpr, fn)`，cron 表达式标准 5/6 段。

## 13. 事件系统（server/events/ + SSE）

- 内存 Broker，事件类型包括：`ScanStatus`（扫描进度）、`RefreshResource`（数据变更）、`NowPlayingCount`、`Playback` 等；
- 推送端点：`GET /api/events`（SSE，需 Authenticator + JWTRefresher）；
- 扫描进度经 `rate.Sometimes` 限频广播（`controller.go:347-388`），Web UI 实时显示扫描进度条。

## 14. 服务端日志要点（NAS 排障参考）

Navidrome 日志级别默认 info（`ND_LOGLEVEL` 可调 debug）。常见关注点：

- **扫描**：`Scanning folder "..."`、`Importing N tracks`、`Found missing tracks`、`Scan completed` —— 新歌没出现先看扫描是否完成；
- **转码**：`Transcoding ... to ... (bitrate)`、`Too many concurrent transcodes`（429）—— 转码风暴或缓存未命中；
- **认证失败**：`Invalid credentials`（`model.ErrInvalidAuth`）—— 客户端 salt/token 算法或密码错误；
- **watcher**：`Received N filesystem events`、`Watcher debounce` —— 文件监听是否生效（NFS 挂载等场景 notify 可能失效）；
- **启动**：`Navidrome server is ready!` 与 `FFmpeg not found`（缺 ffmpeg 时转码不可用，直传仍可）；
- **DB**：`Running N migrations`、`ANALYZE` —— 版本升级迁移。

Luobo 客户端自身在 `debugPrint('[Musly] →/← ...')` 记录每个 Subsonic 请求与耗时，可与服务端日志对照定位慢请求（如转码流 429、封面 404）。

## 15. 与 Luobo 客户端对接要点（对照表）

| 客户端行为（lib/services/subsonic_service.dart） | 服务端对应实现 | 备注 |
|---|---|---|
| `t/s` token+salt 认证（`_getAuthParams`，默认） | `validateCredentials` token 分支：`md5(password+salt)` | salt 任意随机 8 位即可，服务端不校验格式 |
| `useLegacyAuth` → `p=` 明文 | `pass == user.Password`，兼容 `enc:` 前缀 | |
| `ping` 取 `serverType/serverVersion` | `newResponse` 输出 `type="navidrome"`、`serverVersion` | 客户端透传展示 |
| `stream` + `maxBitRate/format` | `ResolveRequest` → DirectPlay/转码决策 | 开转码时客户端绕过本地缓存直连 ExoPlayer |
| `stream` + `estimateContentLength=true` | `EstimatedContentLength = duration×bitrate/8×1024` | 解决转码流时长/拖动（#170） |
| `getCoverArt` size=600 + 固定 salt `musly_stable` | 缓存键含 size；URL 稳定才能命中磁盘缓存 | 客户端 3 档尺寸策略（120/300/600） |
| `scrobble`（start/finish，失败入离线队列补发） | `PlayTracker` 会话 + `incPlay` + buffered scrobbler | 服务端 429/网络抖动不影响客户端，客户端本地补发 |
| `star/unstar/setRating/getStarred2` | `annotation` 表 + `average_rating` 重算 | 收藏多端同步 |
| `search3` | FTS5/bm25（CJK 自动 LIKE） | |
| `getLyricsBySongId` | structuredLyrics（含 enhanced cue） | 客户端三级回退：离线缓存 → Subsonic → LRCLIB/网易云 |
| `updatePlaylist` 重复 `songIdToAdd` 参数 | `p.Strings("songIdToAdd")` 多值解析 | Navidrome 不识别 `songIdToAdd[i]` 形式（客户端注释） |
| LAN/远程双地址探测 | 无特殊处理，任意可达地址均可 | 客户端 `resolveActiveUrl` 3s 超时探测 |

## 16. NAS 部署参考（Docker）

```yaml
services:
  navidrome:
    image: deluan/navidrome:latest
    ports:
      - "4533:4533"
    environment:
      ND_SCANSCHEDULER: "0"            # 关闭定时扫描，靠 watcher 增量（NAS 上注意网络存储 notify 兼容性）
      ND_LOGLEVEL: info
      ND_SESSIONTIMEOUT: "48h"
      ND_BASEPATH: ""                  # 反向代理子路径时设置
    volumes:
      - /path/to/data:/data            # navidrome.db + cache/(transcoding,images,plugins)
      - /path/to/music:/music:ro       # 音乐库（只读即可）
    restart: unless-stopped
```

数据目录布局（`conf/dir.go` + 各模块）：

```
/data/
├── navidrome.db            # SQLite（WAL: -wal/-shm）
├── cache/
│   ├── transcoding/        # 转码缓存（100MB）
│   ├── images/             # 封面缩略图缓存（100MB）
│   └── plugins/            # 插件
├── artwork/                # 手动上传/外部抓取的实体封面
└── plugins/                # 插件配置
```

关键配置（`conf/configuration.go` 默认值）：`ND_MUSICFOLDER=./music`、`ND_SCANNER_SCHEDULE="0"`、`ND_SCANNER_SCANONSTARTUP=true`、`ND_SCANNER_EXTRACTOR=taglib`、`ND_TRANSCODINGCACHESIZE=100MB`、`ND_IMAGECACHESIZE=100MB`、`ND_TRANSCODING_MAXCONCURRENT`（默认不限）、`ND_JELLYFIN_ENABLED=false`、`ND_BACKUP_SCHEDULE`（默认禁用）、`ND_SESSIONTIMEOUT=48h`。

---

*文档基于 navidrome 源码 commit `279ff98`（2026-08-02）撰写；如需核对细节可对照 /tmp/navidrome 或官方仓库。*
