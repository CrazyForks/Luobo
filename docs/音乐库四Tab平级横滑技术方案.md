# Luobo 音乐库四 Tab 平级横滑技术方案

> 状态：方案设计 v1.0（2026-08-05，待 review 放行）
> 范围：音乐库四个 tab（服务端模式 `Artists / Albums / Songs / Faves`，本地模式另含 `Genres / Years`）从"原地跳变切换"改为**平级左右无缝滑动**（手指跟手、页面横滑、状态保活）。纯客户端 UI 结构改造，**不动数据层/服务层/推荐引擎**
> 设计约束：tab 列表随模式动态（4 / 6）；每页独立纵向滚动且切换不丢滚动位置；`_ArtistScrubber` 字母索引照常工作；桌面端（macOS/Windows）同步可用；与「音乐库艺术家页改版技术方案」**只重叠文件、不重叠改动**（本方案改结构，那份改 Artists 页内容）
> 实施进度：⬜ 未开工（待用户「开始 code」）

---

## 1. 背景与目标

### 1.1 用户反馈的痛点

1. 音乐库四个 tab 不像"平级页面"：切换是内容原地淡入淡出，不是左右滑动
2. 已有滑动手势但**不跟手**：手指拖动过程中内容完全不动，松手才跳过去，体感像"点了按钮"
3. 切换 tab 会丢掉列表滚动位置（Albums/Songs 每次切换回到顶部附近）

### 1.2 代码实证的根因

| 根因 | 证据 | 本次是否解决 |
|---|---|---|
| 整个音乐库是**一个共享纵向 `CustomScrollView`**，四个 tab 不是独立页面 | `library_screen.dart:124`（build 唯一的滚动容器），tab 切换只是 `setState` 改 `_selectedFilter`（`:40`） | ✅ 拆为每页独立滚动视图 |
| 切换无横滑视觉，只有原地淡入淡出 | `AnimatedSwitcher`（`:230-289`，`key: ValueKey(_selectedFilter)`，200ms） | ✅ 改为 PageView 页面横滑 |
| 现有滑动是"松手判定跳变"而非跟手 | `GestureDetector`（`:106-123`）：`onHorizontalDragUpdate` 只累加 `_swipeDelta`，`onHorizontalDragEnd` 判断 `distance ≥ 30 && velocity ≥ 300` 才切；期间无任何位移反馈 | ✅ 删除该手势，交给 PageView 原生跟手 |
| 切换即重建内容，滚动位置丢失 | `ValueKey(_selectedFilter)` 每次切换重建整列；仅 Artists 因 `_artistsScrollController` 常驻而保留位置（`:44`） | ✅ PageView 页保活，Albums/Songs/Faves 也保留位置 |
| tab 头是横向滚动 FilterChip 行，非平级 TabBar | `SingleChildScrollView` + `FilterChip`（`:188-226`），选中态与页面无联动动画 | ⚠️ 保留 chips 或改 TabBar 风格（§5.1 待拍板） |

### 1.3 目标

- **平级感**：四个 tab 是横向可滑动的兄弟页面，手指拖动实时跟手，松手惯性落页
- **状态保活**：切走再切回，各 tab 纵向滚动位置、Artists 字母索引高亮均保留
- **零数据层改动**：`_getFilteredItems`（`:486` 起）与各 tab 内容构建逻辑整体复用，只改容器与编排
- **双向联动**：点 chip 切页（动画滚动）⇄ 横滑切页（chip 选中态同步）

---

## 2. 现状结构盘点

### 2.1 布局结构（build 全貌，`library_screen.dart:100-484`）

```
Scaffold
└─ GestureDetector（onHorizontalDragUpdate/End 手动滑动手势，:106-123）
   └─ CustomScrollView（唯一纵向滚动容器，:124）
      ├─ SliverAppBar（pinned+floating，expandedHeight 60，标题+刷新/搜索/+/设置，:126-174）
      ├─ SliverToBoxAdapter：FilterChip 行（:175-229）
      ├─ SliverToBoxAdapter：AnimatedSwitcher —— Faves 文件夹磁贴（_SpotifyLibraryTile ×5，:230-289）
      └─ Consumer<LibraryProvider>：per-filter 内容（:290-478）
         ├─ 'Artists'：字母分组 chip 瀑布流 ListView + 右缘 _ArtistScrubber（:305-459，_artistsScrollController :343）
         └─ 其余：SliverList（_getFilteredItems 结果，:471-476）
      └─ SliverToBoxAdapter：SizedBox 150 底部留白（迷你播放器避让，:479）
```

### 2.2 tab 列表与内容口径

| Filter | 服务端 | 本地模式 | 内容构建位置 |
|---|---|---|---|
| Artists | ✅ | ✅ | 瀑布流分支 `:305-459`（唯一特例） |
| Albums | ✅ | ✅ | `_getFilteredItems :528-556` → SliverList |
| Songs | ✅ | ✅ | `_getFilteredItems :572-584` → SliverList |
| Faves | ✅ | ✅ | 文件夹磁贴 `:236-285` + `_getFilteredItems :494-525` → SliverList |
| Genres | ❌ | ✅ | `_getFilteredItems :586-611` → SliverList |
| Years | ❌ | ✅ | `_getFilteredItems :613+` → SliverList |

- 动态列表来源：`_getFilters`（`:91-98`）= 本地模式 6 项、服务端 4 项
- 空态：非 Artists 且 items 为空 → `_LibraryEmptyState`（`:294-301`）；Artists 空 → 同组件（`:308-315`）
- 刷新/搜索/新建歌单/设置均为 AppBar 动作（`:138-173`），与 tab 无关，保留在共享头部

### 2.3 手势冲突面（现状即存在，改造后需复核）

| 横向手势来源 | 位置 | 与横滑的冲突 |
|---|---|---|
| FilterChip 行 `SingleChildScrollView` | `:188-189` | 窄屏溢出时会抢横向手势（§4.5 处理） |
| 各 tab 内部列表 | 纵向滚动 | 无冲突 |
| Artists 右缘 `_ArtistScrubber` | `:432-455` | 纵向 drag，无冲突 |
| 桌面端鼠标横向拖拽 | — | PageView 原生支持，需验证 |

---

## 3. 方案选型

### 3.1 方案 A：PageView 横滑（推荐）

结构改为 **Column(共享头部 + Expanded(PageView))**，每页独立滚动视图：

```
Scaffold
└─ Column
   ├─ 共享头部（固定）
   │  ├─ AppBar（原 SliverAppBar 内容；现 pinned+floating+expandedHeight 60，固定后视觉等价）
   │  └─ FilterChip 行（或 TabBar 风格，§5.1 待拍板）
   └─ Expanded
      └─ PageView.builder（controller: PageController，onPageChanged 同步 _selectedFilter）
         ├─ Page 0 Artists：现有瀑布流 + _ArtistScrubber（原样搬入）
         ├─ Page 1 Albums：SliverList（_getFilteredItems('Albums')）
         ├─ Page 2 Songs：SliverList（_getFilteredItems('Songs')）
         └─ Page 3 Faves：文件夹磁贴 + SliverList（_getFilteredItems('Faves')）
            （本地模式追加 Genres / Years 两页）
```

要点：

1. **跟手**：PageView 手指拖动实时位移 + 惯性回弹，天然"无缝"
2. **保活**：PageView 默认只构建视口±cacheExtent 页；加 `AutomaticKeepAliveClientMixin` 或直接让每页持自己滚动控制器即可保留滚动位置
3. **删除** `_swipeDelta` / `GestureDetector` / `AnimatedSwitcher` 三处现有跳变逻辑
4. 每页底部保留 ~150 留白（迷你播放器避让，`main_screen.dart:551` MiniPlayer 悬浮在底部导航上方）

### 3.2 方案 B：保留共享滚动视图，做"跟手 Transform"（备选）

不引入 PageView：`onHorizontalDragUpdate` 时用 `Transform.translate` 按 `_swipeDelta` 平移内容列，松手再 `setState` 切到相邻 tab。改动约 30 行。

- 优点：diff 最小（~0.5~1 天）
- 缺点：仍是"单页跟手后跳切"，页面不并列、无惯性落页，观感比方案 A 差一档；AnimatedSwitcher 淡入淡出仍在

### 3.3 对比与建议

| 维度 | A PageView | B Transform 跟手 |
|---|---|---|
| 平级横滑观感 | ✅ 标准 Spotify/Apple Music 形态 | ⚠️ 半成品 |
| 代码量 | 重构 build + 每页提取（约 150~250 行改动） | ~30 行 |
| 状态保活 | ✅ 每页独立滚动控制器 | ❌ 仍整体重建 |
| 维护成本 | 低（框架原生） | 高（手写手势状态机） |
| 风险 | 中（手势仲裁、scrubber 重绑） | 低 |

**建议方案 A**：本次的核心诉求就是"平级 + 无缝"，B 只解决"跟手"不解决"平级"。方案 A 单文件改造、不碰数据层，工作量可控（§7）。

---

## 4. 架构设计（结构先行）

### 4.1 页面拆分方式（待拍板，见 §11）

- **方式 1（推荐）**：单文件内提取 4 个私有 widget（`_ArtistsPage` / `_AlbumsPage` / `_SongsPage` / `_FavesPage`），`library_screen.dart` 保留头部 + PageView 编排。改动集中、diff 可控，与「艺术家页改版」的 `:303-455` 整段替换互不干扰（页内再改内容即可）
- **方式 2**：新建 `lib/screens/library/` 目录，每页独立文件。文件更小可读性更好，但引入 5~6 个新文件

### 4.2 状态同步（单一事实来源）

```
_selectedFilter（String，:40 保留） ⇄ PageController
  ├─ chip onSelected（:202-205）→ _pageController.animateToPage(idx, 250ms, easeOutCubic)
  ├─ PageView onPageChanged(idx) → setState(_selectedFilter = filters[idx])
  └─ 初始页 = filters.indexOf(_selectedFilter)
```

- `_selectedFilter` 仍是唯一状态源，`_getFilteredItems` 等现有逻辑零改动
- 删除 `_swipeDelta`（`:41`）与 `GestureDetector`（`:106-123`）

### 4.3 页面保活与滚动位置

- 每页 `AutomaticKeepAliveClientMixin`（`wantKeepAlive: true`），PageView 默认只回收视口外页面，keepalive 后不回收
- Albums/Songs/Faves 页各自持有 `ScrollController`（或依赖 keepalive + PageStorageKey）；Artists 沿用现有 `_artistsScrollController`（`:44`）
- 实现选择：keepalive 后即使无 ScrollController 也能保位置（PageStorage 自动），Artists 因 scrubber 跳转需要 controller，其余页可不建 controller 省事

### 4.4 Artists 页特殊处理

- 现有瀑布流 `ListView(controller: _artistsScrollController)`（`:342-344`）+ `_ArtistScrubber`（`:432-455`）**原样搬入 `_ArtistsPage`**，无需改跳转逻辑（`_letterIndexMap` 重算依赖不变）
- 「音乐库艺术家页改版技术方案」届时替换的是 `_ArtistsPage` **内部**内容，PageView 容器不受影响

### 4.5 手势冲突矩阵（改造后）

| 手势 | 处理 |
|---|---|
| PageView 横向滑（页面主体区域） | ✅ 框架原生，页间跟手 |
| FilterChip 行横向拖 | 行内可滚动时归行（滚动看更多 chips）；行不溢出时拖拽穿透到 PageView。**窄屏 6 chips（本地模式）会溢出** → 若改 TabBar 风格（§5.1 选项 2）则交给 `TabBarView` 仲裁，彻底无冲突 |
| 各页内纵向滚动 | PageView 横向、列表纵向，方向正交，互不抢 |
| `_ArtistScrubber` 纵向拖 | 正交，无冲突 |
| 桌面端鼠标 | PageView 支持鼠标拖拽；如需要可加键盘 ←/→（可选） |

### 4.6 动态 tab 列表（4 / 6）

- PageView 页数 = `_getFilters(context).length`（`:91-98`），随模式变化；`PageController(initialPage)` 在模式切换时需 clamp 到有效范围（服务端 4 页 ⇄ 本地 6 页切换时 `_selectedFilter` 可能越界 → 复位到 0 或最近有效页）

### 4.7 桌面端

- `LibraryScreen` 在 `MainScreen` 桌面分支的 `IndexedStack` 中渲染（`main_screen.dart:387-390`），本次改造后仍为单个屏幕，不影响桌面侧栏导航
- 验证项：macOS 窗口鼠标拖拽切页、侧栏点击库入口后初始页正确

---

## 5. UI 层设计

### 5.1 头部样式（待拍板，见 §11）

| 选项 | 描述 | 优劣 |
|---|---|---|
| 1. 保留 FilterChip 行（最小改动） | 头部 = AppBar + 现 chips 行（`:188-226`） | 视觉零变化；窄屏 6 chips 溢出时行内滑动与横滑有局部竞争（§4.5） |
| 2. 改 `TabBar`（`isScrollable: true`）+ `TabBarView` | 框架级手势仲裁，滑动/点按均标准 | 视觉从胶囊 chip 变下划线标签，与 Apple Music 风格更近但改动稍大 |

> 注：两者都保留现有 `_selectedFilter` 状态模型（§4.2），切换成本低；建议先选项 1 验证横滑体验，如需再上选项 2。

### 5.2 切换动画

- PageView 自带跟手 + 惯性；`animateToPage` 用 `Curves.easeOutCubic`、250ms
- 移除 `AnimatedSwitcher`（`:231`）淡入淡出

### 5.3 底部留白

- 每页底部保留 ~150 留白（现 `:479`），迷你播放器避让不变

---

## 6. 改动文件清单与实施状态

| 文件 | 改动 | 状态 |
|---|---|---|
| `lib/screens/library_screen.dart` | build 重构：共享头部（AppBar + chips 行）提出固定 Column；`GestureDetector`/`_swipeDelta`/`AnimatedSwitcher` 删除；引入 `PageController` + `PageView.builder`；提取 `_ArtistsPage/_AlbumsPage/_SongsPage/_FavesPage`（方式 1） | ⬜ |
| `lib/screens/library_screen.dart` | `_getFilteredItems` 与各 tab 内容逻辑**整体搬移不修改**；`_ArtistScrubber`/`_letterIndexMap`/`_artistsScrollController` 移入 `_ArtistsPage` | ⬜ |
| `lib/l10n/app_en.arb` + `app_zh.arb` | 无新增文案（chips/TabBar 文案已有） | — |
| `test/` | 无逻辑改动，不新增单测；`flutter analyze` + 现有单测回归 | ⬜ |

---

## 7. 工作量估计

| 项 | 估计 |
|---|---|
| build 重构 + 页面提取（核心） | ~0.5 天 |
| 状态同步 / 保活 / 模式切换（4⇄6）边界 | ~0.25 天 |
| Artists scrubber 重绑 + 手势仲裁排查 | ~0.25 天 |
| 真机（Android）+ 桌面验证回归 | ~0.5 天 |
| **合计** | **约 1.5~2 个工作日**（单文件，无数据层/服务层改动） |

---

## 8. 风险与验证

| 风险 | 影响 | 对策 |
|---|---|---|
| `_ArtistScrubber` 滚动绑定随页面拆分失效 | Artists 页字母索引不跳转 | 搬移时连同 `_artistsScrollController` 一起放入 `_ArtistsPage`，保持 controller 唯一归属；真机验证 |
| FilterChip 行横向手势与 PageView 竞争（窄屏 6 chips） | 在 chip 行上滑动切不了页 | 选项 1：行可滚时接受局部行为；选项 2：改 TabBarView 仲裁（§5.1） |
| 模式切换（本地 6 ⇄ 服务端 4）页数变化 | `_selectedFilter` 越界 | PageView 页数按 `_getFilters` 动态，切换时 clamp 复位（§4.6） |
| 头部固定后与原 SliverAppBar 行为差异 | 滚动时头部不随滚动收放 | 现为 pinned+floating（`:127-128`）+ expandedHeight 60，实为常驻，固定后视觉等价 |
| 桌面端 IndexedStack 内 PageView | 鼠标拖拽/初始页 | §4.7 验证项 |
| 与「艺术家页改版」同文件 | 双方案冲突 | 本方案只动结构（build 编排），艺术家改版只动 `_ArtistsPage` 内容；建议本方案先落地（结构先行），艺术家改版在其上叠加 |

### 验证步骤（开工后）

1. `flutter analyze` 无 error；现有单测全绿
2. Android 真机：四 tab 跟手横滑、惯性落页、chip 点按动画切页、双向选中态同步
3. 切 tab 后回退：Albums/Songs 滚动位置保留；Artists 字母索引拖动跳转正常
4. 本地文件模式：6 tab 横滑、模式切换后初始页正确
5. macOS 桌面：鼠标拖拽切页、侧栏进库初始页正确

---

## 9. 与「音乐库艺术家页改版技术方案」的边界

| 维度 | 本方案（四 Tab 横滑） | 艺术家页改版（另一方案） |
|---|---|---|
| 改什么 | tab 容器结构：单滚动视图 → 头部 + PageView | Artists 页内容：chip 瀑布流 → 方形封面网格 + 常听 shelf |
| 落点 | build 编排（`:100-484` 层） | `_ArtistsPage`（即原 `:303-455`）内部 |
| 冲突 | 无（后者在前者拆分出的页面内继续改） | 建议顺序：横滑先落地，艺术家改版叠加 |

---

## 10. 不做的事

- ❌ 不改顶层底部导航（首页/音乐库/搜索三个主 tab，`main_screen.dart`）——仅音乐库内部四 tab
- ❌ 不动 `_getFilteredItems` 的数据口径/排序（Albums 用 `cachedAllAlbums`、Songs 用 `cachedAllSongs` 等现状保留）
- ❌ 不做 tab 顺序自定义/长按拖拽排序
- ❌ 不做手势参数魔改（跟手/惯性均用框架默认）
- ❌ 不新增第三方依赖（PageView/TabBarView 均为 Flutter 内置）
- ❌ 不新增 l10n 文案

---

## 11. 待拍板决策清单（review 时确认）

| # | 决策点 | 推荐 | 备选 |
|---|---|---|---|
| 1 | 方案选型 | A PageView（§3.1） | B Transform 跟手（§3.2） |
| 2 | 页面拆分方式 | 单文件私有 widget（方式 1） | 新建 `lib/screens/library/` 目录（方式 2） |
| 3 | 头部样式 | 先保留 FilterChip（选项 1），横滑体验验证后再定是否上 TabBar | 直接上 TabBar + TabBarView（选项 2） |
