# Ultrasonic 客户端技术文档（源码解析 + Luobo 对接参考）

> 状态：源码研究完成（2026-08-05）
> 范围：Ultrasonic Android 客户端整体架构、Subsonic API 客户端实现、播放/下载引擎、缓存与离线机制、数据持久化、UI 层、Android 系统集成（Android Auto / 桌面小部件），以及与 Luobo（Musly）客户端的对接参考
> 源码版本：commit `1d50ee38`（2026-08-05，develop），版本 4.9.0（versionCode 131），仓库 gitlab.com/ultrasonic/ultrasonic，GPL-3.0

## 1. 项目概述

Ultrasonic 是一个 **Kotlin** 编写的开源 Android 音乐流媒体客户端（GPL-3.0），对接 **Subsonic API 1.7.0+** 兼容服务器（Subsonic / Airsonic-Advanced / Navidrome / Supysonic / Ampache 均验证可用）。Navidrome 实现了 Subsonic API，因此 Ultrasonic 也是 Navidrome 生态中最活跃的 Android 客户端之一，对 Luobo 有直接的架构参考价值。

核心特性：

- 多服务器（Multi-server）管理，服务器配置存 Room、活动服务器 id 存 SharedPreferences；
- Subsonic API 全量覆盖：媒体库、搜索、播放列表、Podcast、歌词、书签、分享、聊天、Jukebox、评分/收藏、打点（scrobble）；
- **自动协议版本协商**：从每个响应中解析 `version` 字段，动态升降客户端支持的 API 版本并约束参数；
- 双密码加密方式（`enc:` hex 与 MD5+salt），按服务端 API 版本自动切换；
- ExoPlayer（Media3）本地播放 + 可选的服务器端 Jukebox 播放双后端；
- 三级缓存：本地文件（下载）缓存 + 内存 TTL 缓存 + Room 元数据缓存；支持完整离线模式；
- 断点续传下载（HTTP Range + `.partial` 文件），前台服务 + WifiLock 保活；
- Android Auto（Media3 MediaLibraryService 浏览树 + 自定义按钮 + 语音搜索）、桌面小部件、蓝牙耳机控制；
- ReplayGain 音量补偿、系统级均衡器（Equalizer）。

### 1.1 技术栈

| 组件 | 选型 | 版本 | 说明 |
|---|---|---|---|
| 语言 | Kotlin | 2.4.10 | JVM 21 toolchain |
| 构建 | Gradle / AGP | 9.6.1 / 9.2.1 | settings.gradle 声明 3 个模块 |
| 网络 | Retrofit 3 + OkHttp 5 + Jackson 2.22 | — | converter-jackson，拦截器做认证/版本/范围 |
| 播放 | androidx.media3（ExoPlayer） | 1.10.1 | exoplayer / session / datasource / okhttp |
| 依赖注入 | Koin | 4.2.2 | `UApp.startKoin()`，5 个 module |
| 数据库 | Room（KSP） | 2.8.4 | 两库：AppDatabase + 每服务器 MetaDatabase，schema 导出到 `ultrasonic/schemas/` |
| 图片 | Coil 3 | 3.5.0 | 自定义 CoverArtFetcher / AvatarFetcher |
| 响应式 | RxJava 3 / RxAndroid | 3.1.12 | RxBus 事件总线 + DownloadService 状态 |
| 列表 | Drakeet MultiType | 4.3.0 | 自定义 BaseAdapter + 异步 DiffUtil |
| 导航 | AndroidX Navigation + SafeArgs | 2.9.8 | 单 Activity + Drawer + nav graph |
| 其他 | Material、ConstraintLayout、fastscroll、colorpicker、Timber、detekt/ktlint | — | — |

构建关键配置（`ultrasonic/build.gradle`）：

- `minSdk 26 / targetSdk 37 / compileSdk 37`（`gradle/versions.gradle`）；
- release 开启 minify + shrinkResources，proguard 按库拆分文件（`ultrasonic/minify/`）；
- debug 用 `applicationIdSuffix = '.debug'`（与发布包隔离，Luobo 不用此方案——见 Luobo 约定）；
- `resourceConfigurations` 只保留 17 种语言，缩小包体。

### 1.2 模块结构

```
settings.gradle
├── :core:domain          # 领域模型（不依赖 Android）
├── :core:subsonic-api    # Subsonic REST API 客户端库（纯 Kotlin + Retrofit/OkHttp/Jackson）
└── :ultrasonic           # Android App 主模块（UI/服务/数据/集成）
```

顶层目录：

```
core/subsonic-api/src/main/kotlin/org/moire/ultrasonic/api/subsonic/
    SubsonicAPIClient.kt              客户端入口：OkHttpClient + Retrofit + 版本协商
    SubsonicAPIDefinition.kt          全部 REST 端点声明（Retrofit 接口）
    SubsonicAPIVersions.kt            API 版本枚举 + 版本字符串解析
    ApiVersionCheckWrapper.kt         按版本拦截不允许的调用/参数
    VersionAwareJacksonConverterFactory.kt  响应转换时回调最新版本
    interceptors/                     PasswordHex/MD5、Proxy、Version、RangeHeader
    models/ response/                 API 数据模型与响应包装（SubsonicResponse）

core/domain/src/main/kotlin/org/moire/ultrasonic/domain/
    Album.kt Artist.kt Track.kt MusicDirectory.kt ...  领域模型

ultrasonic/src/main/kotlin/org/moire/ultrasonic/
    app/UApp.kt                       Application：Koin 启动 + Coil 装配
    di/                               Koin 模块（5 个）
    data/                             Room 数据库 + DAO + ActiveServerProvider + CachedDataSource
    service/                          MusicService 三实现 + PlaybackService + DownloadService/Task
    fragment/ model/ adapters/ view/  UI 层
    activity/NavigationActivity.kt    唯一 Activity（Drawer + NavHost）
    imageloader/                      封面/头像加载
    provider/ receiver/ audiofx/      桌面小部件、广播接收器、均衡器
    subsonic/                         ImageLoaderProvider、RestErrorMapper 等
    util/                             Settings、Storage、FileUtil、Constants 等
```

## 2. 整体架构与启动流程

### 2.1 启动流程

`UApp.onCreate()`（`ultrasonic/src/main/kotlin/org/moire/ultrasonic/app/UApp.kt:63-86`）：

1. debug 构建种植 Timber `DebugTree`；
2. IO 协程内异步初始化：文件日志（可选）→ 预填充 `FileUtil.cachedUltrasonicDirectory` → 触发 `Storage.mediaRoot` 惰性求值 → 判断首启；
3. `startKoin()` 注册 5 个模块：`applicationModule`、`appPermanentStorage`、`baseNetworkModule`、`musicServiceModule`、`mediaPlayerModule`。

debug 构建同时开启 StrictMode 全量检测（`UApp.kt:53-56`）。

### 2.2 依赖注入图（Koin）

- `applicationModule`（`di/ApplicationModule.kt`）：`ActiveServerProvider`、`ImageLoaderProvider`、`CacheCleaner` 单例；
- `appPermanentStorage`（`di/AppPermanentStorageModule.kt`）：Room `AppDatabase`（含 10 个手写迁移）、`ServerSettingDao`、`ServerSettingsModel`（唯一用 Koin `viewModel {}` 注册的 VM）；
- `baseNetworkModule`：基础 `OkHttpClient`（API 客户端再在其上 newBuilder）；
- `musicServiceModule`（`di/MusicServiceModule.kt:27-68`）：
  - `named("ServerInstance")` 活动服务器 id；`named("ServerID")` = `abs((url+id).hashCode())`（用于元数据库文件名）；
  - `SubsonicClientConfiguration` 从活动服务器读取（url/用户名/密码/`minimumApiVersion`），`isRealProtocolVersion = server.minimumApiVersion != null`；
  - `SubsonicAPIClient` 单例；
  - `MusicService` 两个具名实现：**online** = `CachedMusicService(RESTMusicService(...))`（装饰器套网络实现），**offline** = `OfflineMusicService()`；
- `mediaPlayerModule`：`MediaPlayerManager`、`MediaPlayerLifecycleSupport`、`ExternalStorageMonitor`、`RatingManager` 等。

### 2.3 三层数据流总览

```
fragment → GenericListModel(LiveData) → MusicService
                                           ├─ CachedMusicService（读缓存优先，穿行网络）
                                           │    ├─ Room MetaDatabase（per-server）
                                           │    ├─ LRUCache + TimeLimitedCache（内存 TTL）
                                           │    └─ RESTMusicService（真网络）
                                           └─ OfflineMusicService（Room serverId=0，纯本地）

播放：PlaybackService(MediaLibraryService) → ExoPlayer
       DataSource 链：CachedDataSource → ResolvingDataSource → OkHttpDataSource
下载：DownloadService(前台) → DownloadTask → RESTMusicService.getDownloadInputStream()
       （断点续传 Range → .partial → 完成后 rename → .complete/.pinned + 写离线 DB + 下载封面）
```

## 3. Subsonic API 客户端（core/subsonic-api）—— Luobo 对接核心

### 3.1 客户端装配（SubsonicAPIClient.kt）

`SubsonicAPIClient`（`SubsonicAPIClient.kt:32-146`）构造时：

- **默认请求参数**：拦截器为每个请求追加 `u=<用户名>`、`c=Ultrasonic`（客户端标识）、`f=json`（强制 JSON 而非 XML，`SubsonicAPIClient.kt:66-87`）；
- URL 内含 userinfo 时自动加 `Authorization: Basic` 头（支持 `http://user:pass@host` 形式）；
- 拦截器链顺序：`默认参数 → VersionInterceptor → ProxyPasswordInterceptor → RangeHeaderInterceptor → 可选日志`；
- 允许自签名证书（`allowSelfSignedCertificates()`）与 debug 模式 HEADERS 级日志；
- **60s 读超时**，并特意**禁用 HTTP/2**（OkHttp + ExoPlayer 的已知 bug，见 `SubsonicAPIClient.kt:63` 注释指向 square/okhttp#6749）；
- `isOffline`：`baseUrl == "http://localhost"`（离线假服务器常量 `OFFLINE_DB_URL`）。

### 3.2 端点覆盖（SubsonicAPIDefinition.kt）

约 50 个端点，Luobo 可直接对照：

| 类别 | 端点 |
|---|---|
| 健康/认证 | ping、getLicense、getUser |
| 媒体库 | getMusicFolders、getIndexes、getArtists、getMusicDirectory、getArtist、getAlbum |
| 浏览 | getAlbumList / getAlbumList2、getRandomSongs、getStarred / getStarred2、getSongsByGenre、getGenres、getVideos |
| 搜索 | search（v1）、search2（v1.4+）、search3（v1.8+，ID3） |
| 播放/下载 | **stream.view / download.view**（`@Streaming`，`Range` 头 + `timeOffset` 参数） |
| 收藏/评分 | star、unstar、setRating |
| 播放列表 | getPlaylist(s)、createPlaylist、updatePlaylist、deletePlaylist |
| 打点 | scrobble（time/submission） |
| 其他 | getLyrics、getPodcasts、jukeboxControl、getShares/createShare/deleteShare/updateShare、getChatMessages/addChatMessage、getBookmarks/createBookmark/deleteBookmark、getCoverArt、getAvatar |

### 3.3 协议版本协商（Ultrasonic 最值得借鉴的机制）

三个组件协同，**客户端不再硬编码"服务器只支持某版本"**：

1. `VersionAwareJacksonConverterFactory`（`VersionAwareJacksonConverterFactory.kt:67-87`）：每个响应反序列化后，若根是 `SubsonicResponse` 就回调 `notifier(response.version)`；
2. `SubsonicAPIClient.protocolVersion` setter（`SubsonicAPIClient.kt:52-60`）：更新版本时同步刷新 `VersionInterceptor`（`v=` 参数）与密码拦截器，并回调 `onProtocolChange`；
3. `RESTMusicService.init`（`RESTMusicService.kt:596-603`）：把协商出的最新 `restApiVersion` 写回服务器配置（`ActiveServerProvider.setMinimumApiVersion`），持久化。

`ApiVersionCheckWrapper`（`ApiVersionCheckWrapper.kt:53-368`）是委托包装器：每个端点声明自己要求的 API 版本（如 `getArtists → V1_8_0`），`checkVersion()`/`checkParamVersion()` 在服务器版本不足时抛 `ApiNotSupportedException`。`checkParamVersion` 只在该参数非空时校验（例如 `musicFolderId` 需要 v1.12，不传则不拦截）。首次连服务器（`isRealProtocolVersion == false`）时跳过全部校验。

`SubsonicAPIVersions.getClosestKnownClientApiVersion`（`SubsonicAPIVersions.kt:38-99`）把服务器返回的任意版本串（如 `1.16.1`）归一到已知枚举（1.1.0 … 1.16.0）。

**对 Luobo 的意义**：Dart 端同样应"每次响应读 version → 更新本地已知版本 → 按版本决定是否传某参数"，而不是写死一个版本号。

### 3.4 认证与密码（interceptors/）

- `PasswordHexInterceptor`（`PasswordHexInterceptor.kt`）：`p=enc:<hex>`，用于 **API ≤ 1.12.0**（Subsonic 4.x）；
- `PasswordMD5Interceptor`（`PasswordMD5Interceptor.kt:17-47`）：每请求生成 16 字节随机 salt，追加 `t=MD5(password+salt)`（小写 hex）与 `s=salt`，用于 **API ≥ 1.13.0**；
- `ProxyPasswordInterceptor`（`ProxyPasswordInterceptor.kt:22-27`）：按 `apiVersion < V1_13_0 || forceHexPassword` 选择上述二者；`forceHexPassword` 用于 LDAP 用户（明文密码不可逆）。

### 3.5 Range 与流媒体头（RangeHeaderInterceptor.kt）

- 把 ExoPlayer 传来的 `Range: <offset>` 规范成 `bytes=<offset>-`（RFC 7233）；
- **按 offset 线性加大读超时**：`30s + offset * 0.02ms`（`RangeHeaderInterceptor.kt:8-11,42-43`），因为"offset + 服务端转码"组合下服务器要先转码再回数据，易触发客户端超时——这是流媒体客户端常见的坑。

### 3.6 错误处理

- `SubsonicResponse` 统一包装：`throwOnFailure()`（`Extensions.kt`）在 `error` 存在时抛 `SubsonicRESTException`；
- `RestErrorMapper`（`ultrasonic/.../subsonic/RestErrorMapper.kt`）把异常映射为用户可读错误；
- 首次连接的服务器若 `version` 缺失/非法，`VersionAwareResponseBodyConverter` 静默忽略（`VersionAwareJacksonConverterFactory.kt:78-82`）。

## 4. 领域层与数据转换

`core/domain` 定义纯净领域模型（`Album`、`Artist`、`Track`、`MusicDirectory`、`Playlist`、`Genre`、`SearchResult` 等），不依赖 Android/网络库。`Track` 含 `suffix/size/duration/bitRate/track/discNumber/year/genre/starred/userRating/artworkUrl` 等完整元数据。

API 模型 → 领域模型转换器位于 `ultrasonic/.../domain/API*Converter.kt`（如 `APIMusicDirectoryConverter`、`APIAlbumConverter`），转换时统一附加 `activeServerId`，使领域对象天然携带服务器归属，供离线库使用。

## 5. MusicService 三实现（缓存与离线核心）

`MusicService` 接口（`service/MusicService.kt:30-199`）约 60 个方法，三个实现各司其职：

### 5.1 RESTMusicService —— 纯网络

- 每个方法 `API.xxx().execute().throwOnFailure()` 后转领域模型（`RESTMusicService.kt`）；
- 搜索自动降级链：`search3 → search2 → search`（`RESTMusicService.kt:145-154`，ID3 与否取决于 `shouldUseId3Tags()`）；
- 流：`getDownloadInputStream(song, offset, maxBitrate, save)` 区分 `download.view`（save=true）与 `stream.view`，通过 `response.responseHttpCode == 206` 判断"部分内容"（`RESTMusicService.kt:370-395`）；
- `getStreamUrl` 技巧（`RESTMusicService.kt:404-438`）：用 OkHttp 拦截器返回 **dummy 响应**（code 100），从而拿到"已注入全部认证参数但未实际执行"的最终 URL——用于第三方播放器/系统播放器直接播放；
- `jukeboxControl` 系列直通 Jukebox 操作。

### 5.2 CachedMusicService —— 缓存装饰器

包在 `RESTMusicService` 外层（`MusicServiceModule.kt:61-63`），读缓存优先、穿行网络后回填：

- **Room 持久缓存**：`cachedArtists/cachedAlbums/cachedIndexes/cachedMusicFolders`（`CachedMusicService.kt:57-60`）；`getArtists/getAlbumsOfArtist/getAlbum/getIndexes/getMusicFolders` 先查 DAO，空则网络拉取并 `upsert`（如 `getAlbumsOfArtist` `CachedMusicService.kt:161-178`）；
- **内存 TTL 缓存**：`LRUCache<String, TimeLimitedCache<...>>`（容量 100）装 `MusicDirectory/Album/UserInfo`，TTL 取 `Settings.directoryCacheTime`（`CachedMusicService.kt:47-54,140-154`）；`cachedLicenseValid` 120s、`cachedPlaylists/cachedPodcastsChannels` 1h、`cachedGenres` 10h；
- **缓存失效**：`checkSettingsChanged()`（`CachedMusicService.kt:334-357`）对比 REST URL 与 musicFolderId，变化即切换 MetaDatabase 实例并清空内存缓存。

### 5.3 OfflineMusicService —— 纯离线

只读 `serverId=0` 的离线 MetaDatabase（`OfflineMusicService.kt`），没有网络调用；离线库由 `DownloadTask` 下载完成时回填（见 §6.4）。

## 6. 播放与下载引擎

### 6.1 PlaybackService（Media3 MediaLibraryService）

`PlaybackService`（`service/PlaybackService.kt:62-493`）继承 `MediaLibraryService`，是"播放器 + 媒体会话 + 系统集成"的枢纽：

- **双后端**：本地 ExoPlayer 或 `JukeboxMediaPlayer`（服务器 Jukebox），`MediaPlayerManager.PlayerBackend` 切换时重建 Player（`PlaybackService.kt:233-278`）；
- **本地 Player 的 DataSource 链**（`PlaybackService.kt:242-278`）：

```
CachedDataSource.Factory(resolvingDataSource)
    └─ ResolvingDataSource.Factory(okHttpDataSource, resolver)
           └─ OkHttpDataSource.Factory(client)
```

  - media URI 用 `|` 分隔的伪 URI：`<songId>|<bitrate>`（`PlaybackService.kt:120-142`），`resolver` 负责调 `getStreamUrl` 得到真 URL、补 `Authorization: Basic` 头（从 URL userinfo 取）、并**移除 media3 自动加的 icy-metadata 头**（AirSonic 兼容）；
  - `CachedDataSource`（`data/CachedDataSource.kt`）先查本地完整文件：命中则本地读流并支持 `skipFully` 精确 seek；未命中转发上游（见 §6.3）；
- **预加载**：`cacheNextSongs()` 在 `onTimelineChanged / onShuffleModeEnabledChanged / onMediaItemTransition / onIsPlayingChanged` 触发，取 `Settings.preloadCount` 首后续曲目交给 `DownloadService.download(highPriority=true)`（`PlaybackService.kt:346-363`）——即**播放即缓存，实现边听边下载**；
- **ReplayGain**：`onTracksChanged` 时按设置（track/album、动态/仅轨）计算音量（`PlaybackService.kt:365-400`）；
- **关机**：`onTaskRemoved`/收到 RxBus 关闭命令 → `releasePlayerAndSession()` → `mediaPlayerManager.serializeCurrentSessionSync()` 落盘 `downloadstate.ser`（`PlaybackService.kt:104-118`）；
- 自定义会话命令：Heart 开/关、Shuffle、Repeat（供 Android Auto 与通知栏使用）。

### 6.2 MediaPlayerManager / 会话恢复

- `PlaybackStateSerializer`（`service/PlaybackStateSerializer.kt`）：`PlaybackState(songs, currentPlayingIndex, currentPlayingPosition, shufflePlay, repeatMode)` 序列化到 `Constants.FILENAME_PLAYLIST_SER = "downloadstate.ser"`；异步写带 AtomicBoolean 防重入；
- `MediaPlayerManager`：订阅 `RxBus.throttledPlaylistObservable` / `throttledPlayerStateObservable`（**300ms 节流**，`RxBus.kt:58-76`）自动落盘；`restore(state, autoPlay)` 重放歌单、恢复 shuffle/repeat 与进度（`MediaPlayerManager.kt:339-361`）；
- `PlaylistTimeline`（`service/PlaylistTimeline.kt`）：自定义 Media3 `Timeline`，维护 shuffle 索引映射，实现单曲循环/列表循环/随机下的前后曲导航。

### 6.3 CachedDataSource（播放直读本地缓存）

`open()` 解析伪 URI 第 3 段为文件路径（`CachedDataSource.kt:60-76`）：命中 `track.getCompleteFile()` 则打开文件流、`skipFully(position)` 定位后返回本地长度（**seek 不消耗网络**）；未命中转发 `upstreamDataSource.open()`。`read()`/`close()` 同样按"本地 or 上游"分流。注意：**播放不写缓存**——写缓存统一走 DownloadService，避免播放线程与下载线程竞争同一文件（`.partial` 只在下载任务中使用）。

### 6.4 DownloadService / DownloadTask（下载引擎）

`DownloadService`（`service/DownloadService.kt`）是 `foregroundServiceType="dataSync"` 的前台服务：

- 任务组织：`PriorityBlockingQueue<DownloadableTrack>` 优先级队列 + `ConcurrentHashMap<String, DownloadTask>` 活动表 + `failedList`（`DownloadService.kt:247-249`）；高优先级（预加载）用小序号，后台任务用递减计数器 `backgroundPriorityCounter`（`DownloadService.kt:255-300`）；
- 并发上限 `Settings.parallelDownloads`，`processNextTracks()` 填满活动槽（`DownloadService.kt:145-154`）；
- 网络/存储不可用时 5s 后重试（`CHECK_INTERVAL`，`DownloadService.kt:167-175`）；WifiLock 保活；全部完成后 `CacheCleaner.cleanSpace()` 并 `stopSelf()`；
- 状态经 `RxBus.trackDownloadStatePublisher` 发布，`observableDownloads`（LiveData）供下载页展示。

`DownloadTask`（`service/DownloadTask.kt`）：

1. `checkIfExists()`：已 pinned/complete 直接跳转状态（含 pinned/complete 互转时刷新元数据）；
2. `download()`：读 `.partial` 文件现有长度 `fileLength`，调 `getDownloadInputStream(track, fileLength, ...)` → 服务器返回 206 即**从断点续传**；`copyWithProgress` 手动节流 50ms 上报进度（未知总长时进度为 null）（`DownloadTask.kt:94-148`）；
3. `afterDownload()`：写离线元数据与封面（`cacheMetadataAndArtwork`，见下）后 rename：pinned → `<title>.ext`，否则 → `<title>.complete.ext`（`DownloadTask.kt:150-173`）；
4. 失败重试：`MAX_RETRIES = 5`，超过置 FAILED（`DownloadTask.kt:183-187`）。

`cacheMetadataAndArtwork`（`DownloadTask.kt:219-273`）：把该曲的 artist/album（含合辑 artist）/track 写入**离线库**（`serverId=0`），并通过 `ImageLoaderProvider` 预下载封面与艺人头像——这就是"下载一首歌后离线也能看全信息"的实现。

### 6.5 文件三态与命名

`FileUtil`（`util/FileUtil.kt:83-90`）每个曲目三种文件：

| 状态 | 文件 | 含义 |
|---|---|---|
| pinned（固定） | `<root>/<artist>/<album>/NN-title.ext` | 用户"固定"，CacheCleaner 不清除 |
| partial（临时） | `NN-title.partial.ext` | 下载中断点续传载体 |
| complete（缓存） | `NN-title.complete.ext` | 可被 CacheCleaner 按容量驱逐 |

命名规则 `<artist>/<album>/NN-title.ext`，非法字符替换为 `-`（`FileUtil.kt:306-356`）；默认根目录 `getExternalFilesDir(null)`，可用 SAF 树 URI 自定义缓存目录（`StorageFile` 实现 DocumentsContract 读写，`util/StorageFile.kt`）。

## 7. 数据持久化

### 7.1 两个 Room 库

| 库 | 实体 | 位置/版本 | 用途 |
|---|---|---|---|
| `AppDatabase` | `ServerSetting`（18 列） | `ultrasonic-database`，v6，10 个手写迁移 | 服务器账号配置（url/密码/能力开关/minimumApiVersion…） |
| `MetaDatabase` | `Artist/Album/Track/Index/MusicFolder` | **每服务器一个文件** `ultrasonic-database-meta-<serverId>`，v3；离线副本 `-meta-0` | 元数据缓存 + 离线曲库索引 |

- 表均带 `serverId` 复合主键 `(id, serverId)`（schema 见 `ultrasonic/schemas/`）；
- `MetaDatabase` 用 `@TypeConverters` 把 `Date ↔ Long`（`data/MetaDatabase.kt:60-66`）；
- `AppDatabase` 迁移从 `MIGRATION_1_2` 到 `MIGRATION_6_5` 手写维护（`data/AppDatabase.kt:34-300`）。

### 7.2 ActiveServerProvider（多服务器 + 离线）

- 活动服务器 id 在 **SharedPreferences**（`Settings.activeServer`，默认 -1），服务器记录在 Room（`data/ActiveServerProvider.kt:251`）；
- 离线模式：`OFFLINE_DB_ID = -1`、index 0，合成一个 `url = "http://localhost"` 的假 ServerSetting（`ActiveServerProvider.kt:219-240`）；`isOffline()` 即 `getActiveServerId() == OFFLINE_DB_ID`；
- 切服务器流程：先发 `activeServerChangingPublisher`，主线程写 `Settings.activeServer` → `resetMusicService()` → 发 `activeServerChangedPublisher`（PlaybackService 收到后重建 Player 以换 OkHttpClient/设置）（`ActiveServerProvider.kt:93-129`）；
- `getActiveMetaDatabase()` 按服务器 id 惰性打开对应库文件，`deleteMetaDatabase(id)` 支持清库（`ActiveServerProvider.kt:131-168`）。

### 7.3 Settings

`util/Settings.kt` + `SettingsDelegate`：SharedPreferences 包装，全部 key 收在 `res/xml/setting_keys.xml`，按类型（Int/String/Boolean）生成 `XXXSetting` 委托属性，供全局 `Settings.xxx` 静态访问。`Constants.kt` 明确标注"不再新增 legacy key"。

## 8. UI 层

- **单 Activity**：`NavigationActivity`（DrawerLayout + MaterialToolbar + NavHostFragment + 底部独立 `NowPlayingFragment` 容器 + NavigationView），nav graph 定义 20+ 目的地（`res/navigation/navigation_graph.xml`），SafeArgs 传参，菜单项 id 与目的地 id 对齐实现 drawer 自动联动（`activity/NavigationActivity.kt:361-422`）；
- **首页**：`MainFragment` 用 ViewPager2 + `FragmentStateAdapter` 装 4 个 Tab：Artists / Albums / Songs / Genres（`fragment/MainFragment.kt:168-225`）；
- **MVVM**：列表模型继承 `GenericListModel(Application)`（AndroidViewModel），暴露 `MutableLiveData`，`viewModelScope + withContext(IO)` 调 MusicService 后 `postValue`；fragment 在 `MultiListFragment.onViewCreated` 统一 `observe → submitList`（`fragment/MultiListFragment.kt:136`）；`RefreshableFragment` + SwipeRefreshLayout 做下拉刷新；
- **列表渲染**：Drakeet MultiType + 自定义 `BaseAdapter`（异步 DiffUtil `SettableAsyncListDiffer`、多选 `BoundedTreeSet`、稳定 id、fastscroll 分组名），行类型注册顺序敏感（最具体在前）；`AlbumRowDelegate`/`AlbumGridDelegate` 按 `LayoutType` 用 MultiType linker 切换列表/封面宫格；
- **分页**：`EndlessScrollListener`（阈值 7）触发 `onLoadMore(page, total, view)`，模型维护 `loadedUntil` 偏移并用 `distinctBy { id }` 去重追加（`fragment/EndlessScrollListener.kt`、`model/TrackCollectionModel.kt:53-67`）；
- **播放页**：底部迷你条 `NowPlayingFragment`（`RxBus` 驱动显隐）+ 全屏 `PlayerFragment`，全部绑定 MediaSession；
- **服务器选择**：`ServerSelectorFragment`（LiveData 列表）+ `EditServerFragment`（表单 + 连接测试，用 **Kotlin Flow** `queryFeatureSupport()` 探测服务器能力后自动勾选功能开关）。

## 9. Android 系统集成

### 9.1 Android Auto（MediaLibrarySessionCallback）

- 浏览树：`mediaId` 用 `|` 分隔的 token（如 `MEDIA_ALBUM_ITEM|albumId|albumName`），`onGetChildren` 分派到各分类加载器（Root → Library/Artists/Albums/Playlists → 随机/收藏/星级/最新/分享/书签/Podcast…）；艺术家超 100（`DISPLAY_LIMIT`）时生成 A-Z 分区索引；专辑列表按 100/页分页并追加 "More" 项；
- 语音搜索：`playFromSearch` 剥掉 "play " 前缀，`musicService.search` 取前 10 播第一个结果（`MediaLibrarySessionCallback.kt:665-722`）；
- 自定义命令：Heart（Love/Dislike）、Shuffle（当前曲不动、洗其余）、Repeat 三态循环（OFF→ALL→ONE），`onConnect/onPostConnect` 注册并下发 custom layout；车机投影（`CONNECTION_TYPE_PROJECTION`）时强制 REPEAT_ALL 并在断开恢复（`configureRepeatMode`）；
- 播放恢复：`onPlaybackResumption` 调 `MediaPlayerLifecycleSupport` 恢复上次会话。

### 9.2 桌面小部件（UltrasonicAppWidgetProvider）

- 显示曲名/艺人/专辑 + 播放/上一曲/下一曲 + 封面（封面经 `AlbumArtContentProvider` 的 `content://` URI 提供，`openFile` 时按需 `downloadCoverArt`）；
- 更新完全**推送驱动**：PlaybackService 在 `onMediaItemTransition`/`onIsPlayingChanged` 调 `notifyTrackChange/notifyPlayerStateChange`（`PlaybackService.kt:416-424`）；
- 按钮经 `UltrasonicIntentReceiver`（`CMD_PROCESS_KEYCODE` + 合成 KeyEvent）转发给播放器。

### 9.3 其他集成

- 通知/权限：Manifest 声明 `FOREGROUND_SERVICE_MEDIA_PLAYBACK`（PlaybackService，exported + MediaLibraryService intent filter，Android Auto 必需）与 `FOREGROUND_SERVICE_DATA_SYNC`（DownloadService）；Android 12+ 前台服务启动受限时发兜底通知（`PlaybackService.kt:426-466`）；
- 蓝牙：`BluetoothIntentReceiver` 监听 A2DP 连接/断开自动播放/暂停；
- 打点：`Scrobbler` 在播放位置超阈值时 `scrobble(id, submission=true)`（标准 Subsonic scrobble，非 Last.fm）；
- 均衡器：`EqualizerController` 绑定 `player.audioSessionId`，提供 5 段预设与自选；
- 图片：Coil 3 `ImageLoader`（内存缓存 = 25% heap，crossfade），`CoverArtFetcher` 构建 `getCoverArt.view?id=&size=` URL，`AvatarFetcher` 拉 `getAvatar`；`ArtworkBitmapLoader` 供 MediaSession 通知栏位图；封面磁盘缓存按 md5 命名 + `folder.jpeg` 约定（`util/FileUtil.kt:160-206`）；
- 事件总线：`RxBus`（PublishSubject/BehaviorSubject 集合）承载跨层事件（播放状态、歌单、服务器切换、主题变更、评分、下载状态、关闭命令等），配合 Koin 全局单例。

## 10. 缓存体系总结（对照 Luobo）

| 层级 | 载体 | 内容 | 策略 |
|---|---|---|---|
| 文件缓存 | 本地 `music/` 目录 `.complete/.pinned/.partial` | 音频流 | 下载即缓存；pinned 免驱逐；CacheCleaner 超容量清理 complete |
| 播放直读 | CachedDataSource | 已下载文件 | ExoPlayer seek 全本地，命中不联网 |
| 内存缓存 | LRUCache(100) + TimeLimitedCache | MusicDirectory/Album/UserInfo/License/Playlists/Genres | TTL 差异化（120s~10h） |
| Room 元数据 | MetaDatabase（per-server + offline） | Artist/Album/Track/Index/MusicFolder | 读缓存优先，刷新时清库重建 |
| 会话持久化 | `downloadstate.ser` | 播放列表+进度+模式 | 300ms 节流落盘，服务销毁同步落盘 |

## 11. 对 Luobo 的可借鉴要点

1. **API 版本协商**：响应头 `version` 回读 + 按版本约束参数（§3.3）——避免写死 1.16.1 导致老服务器/新参数不兼容；
2. **密码双模式**：`enc:` hex（≤1.12）与 MD5+salt（≥1.13），LDAP 用户强制 hex（§3.4）；
3. **Range 头 + 读超时随 offset 放大**：转码服务器上 seek 后拖流稳定（§3.5）；
4. **边播边缓存**：`cacheNextSongs()` 高优先级预加载下 N 首，播放即写盘（§6.1/6.4）；
5. **断点续传**：`.partial` 文件长度 → Range 请求 → rename 收尾，失败重试上限 5（§6.4）；
6. **离线模式设计**：假服务器（url=localhost）+ 独立 `serverId=0` 元数据库，下载完成回填元数据与封面（§6.4/7.2）；
7. **三级缓存分层**：文件 → 内存 TTL → Room，各自职责清晰（§10）；
8. **流 URL 注入认证后不执行请求**：dummy 响应拿最终 URL 技巧（§5.1），可借鉴到 Flutter 外部播放器场景；
9. **DataStore 版 Settings 注意**：本项目仍用 SharedPreferences 委托属性模式，key 集中管理，Luobo 可对照自己的设置模块。

## 12. 目录速查

```
core/subsonic-api/          Subsonic REST 客户端库（版本协商、认证、端点、模型）
core/domain/                领域模型
ultrasonic/src/main/kotlin/org/moire/ultrasonic/
  app/                       Application 入口
  di/                       Koin 依赖注入
  data/                     Room + ActiveServerProvider + CachedDataSource
  service/                  MusicService 三实现 / PlaybackService / DownloadService+Task / Scrobbler / ReplayGain / RxBus
  fragment/ activity/       UI（单 Activity + 20+ Fragment）
  model/ adapters/ view/    ViewModel / MultiType 适配器 / 自定义视图
  imageloader/              Coil 封面/头像
  provider/ receiver/       Widget / ContentProvider / 广播接收
  audiofx/                  均衡器
  util/                     Settings / Storage / FileUtil / Constants / CacheCleaner
ultrasonic/schemas/         Room schema JSON（AppDatabase v6、MetaDatabase v3）
ultrasonic/minify/          Proguard 规则（按库拆分）
```
