# Luobo 音乐库四 Tab 平级横滑技术方案

> 状态：方案设计 v1.3（2026-08-06，v1.2 审查修正 + **实施完成**：analyze 无 error、单测 102 绿（3 失败为改动前已存在）；**待真机验证**）
> 范围：音乐库四个 tab（服务端模式 `Artists / Albums / Songs / Faves`，本地模式另含 `Genres / Years`）从"原地跳变切换"改为**网易新闻/百度 App 首页式：顶部 TabBar + 页面左右滑动切换**（手指跟手、惯性落页、状态保活）。纯客户端 UI 结构改造，**不动数据层/服务层/推荐引擎**
> 设计约束：tab 列表随模式动态（4 / 6）；每页独立纵向滚动且切换不丢滚动位置；`_ArtistScrubber` 字母索引照常工作；桌面端（macOS/Windows）同步可用；与「音乐库艺术家页改版技术方案」**只重叠文件、不重叠改动**（本方案改结构，那份改 Artists 页内容）；样式对齐网易新闻/百度 App 首页（§5.1）
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
| tab 头是横向滚动 FilterChip 行，非平级 TabBar | `SingleChildScrollView` + `FilterChip`（`:188-226`），选中态与页面无联动动画 | ✅ 替换为 `TabBar + TabBarView`（§5.1 定案） |

### 1.3 目标与已确认决策

**目标**：
- **样式（已确认）**：网易新闻/百度 App 首页式——**顶部文字 TabBar + 下划线指示器，内容页左右滑动切换**（手指跟手、惯性落页），对应 Flutter 标准组合 `TabBar + TabBarView`
- **平级感**：四个 tab 是横向可滑动的兄弟页面，不再原地淡入淡出
- **状态保活**：切走再切回，各 tab 纵向滚动位置、Artists 字母索引高亮均保留
- **零数据层改动**：`_getFilteredItems`（`:486` 起）与各 tab 内容构建逻辑整体复用，只改容器与编排
- **双向联动**：点 tab 切页（动画滚动）⇄ 横滑切页（tab 选中态同步）

**已确认决策（2026-08-05）**：

| 决策点 | 选择 |
|---|---|
| 交互样式 | 网易新闻/百度 App 首页式：顶部 TabBar + 左右滑动（Flutter `TabBar + TabBarView`） |
| 方案选型 | 方案 A（§3.1）；方案 B 作废 |
| 头部形态 | 文字标签 + 下划线指示器，`isScrollable: true`（兼容 4/6 tab 动态数量） |

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
| FilterChip 行 `SingleChildScrollView` | `:188-189`（改造后替换为 TabBar） | 现会抢横向手势；TabBar 方案下由 TabBarView 手势仲裁消除（§4.5） |
| 各 tab 内部列表 | 纵向滚动 | 无冲突 |
| Artists 右缘 `_ArtistScrubber` | `:432-455` | 纵向 drag，无冲突 |
| 桌面端鼠标横向拖拽 | — | PageView 原生支持，需验证 |

---

## 3. 方案选型

### 3.1 方案 A：TabBar + TabBarView 顶部横滑（已拍板）

**样式定案**：网易新闻/百度 App 首页式——顶部文字 TabBar（下划线指示器）+ 内容 TabBarView 左右滑动。对应 Flutter 标准组合 `TabBar + TabBarView`（内部即 PageView，手指跟手 + 惯性落页），TabBar 与页面滚动天然联动。

结构改为 **Column(共享头部 + Expanded(TabBarView))**，每页独立滚动视图：

```
Scaffold
└─ Column
   ├─ 共享头部（固定）
   │  ├─ AppBar（原 SliverAppBar 内容；现 pinned+floating+expandedHeight 60，固定后视觉等价）
   │  └─ TabBar（isScrollable: true，文字标签 + 下划线指示器，§5.1）
   └─ Expanded
      └─ TabBarView（TabController 驱动，滑动/点按双向联动）
         ├─ Page 0 Artists：现有瀑布流 + _ArtistScrubber（原样搬入）
         ├─ Page 1 Albums：SliverList（_getFilteredItems('Albums')）
         ├─ Page 2 Songs：SliverList（_getFilteredItems('Songs')）
         └─ Page 3 Faves：文件夹磁贴 + SliverList（_getFilteredItems('Faves')）
            （本地模式追加 Genres / Years 两页）
```

要点：

1. **跟手**：TabBarView（内部 PageView）手指拖动实时位移 + 惯性回弹，天然"无缝"
2. **保活**：TabBarView 默认只构建视口±cacheExtent 页；加 `AutomaticKeepAliveClientMixin` 或直接让每页持自己滚动控制器即可保留滚动位置
3. **删除** `_swipeDelta` / `GestureDetector` / `AnimatedSwitcher` / FilterChip 行四处现有逻辑
4. 每页底部保留 ~150 留白（迷你播放器避让，`main_screen.dart:551` MiniPlayer 悬浮在底部导航上方）
5. TabController 需随 `_getFilters` 数量动态重建（4⇄6，§4.2）

### 3.2 方案 B：保留共享滚动视图，做"跟手 Transform"（**已作废 2026-08-05**）

不引入 PageView：`onHorizontalDragUpdate` 时用 `Transform.translate` 按 `_swipeDelta` 平移内容列，松手再 `setState` 切到相邻 tab。改动约 30 行。

- 优点：diff 最小（~0.5~1 天）
- 缺点：仍是"单页跟手后跳切"，页面不并列、无惯性落页，观感比方案 A 差一档；AnimatedSwitcher 淡入淡出仍在

### 3.3 对比与建议

| 维度 | A TabBar + TabBarView | B Transform 跟手 |
|---|---|---|
| 平级横滑观感 | ✅ 网易新闻/百度 App 首页标准形态 | ⚠️ 半成品 |
| 代码量 | 重构 build + 每页提取（约 150~250 行改动） | ~30 行 |
| 状态保活 | ✅ 每页独立滚动控制器 | ❌ 仍整体重建 |
| 维护成本 | 低（框架原生 TabController） | 高（手写手势状态机） |
| 风险 | 中（TabController 动态重建、scrubber 重绑） | 低 |

**方案 A 已拍板**（2026-08-05）：本次核心诉求是网易新闻式"顶部 tab + 平级滑动"，B 只解决"跟手"不解决"平级"。方案 A 单文件改造、不碰数据层，工作量可控（§7）。

---

## 4. 架构设计（结构先行）

### 4.1 页面拆分方式（待拍板，见 §11）

- **方式 1（推荐）**：单文件内提取 4 个私有 widget（`_ArtistsPage` / `_AlbumsPage` / `_SongsPage` / `_FavesPage`），`library_screen.dart` 保留头部 + PageView 编排。改动集中、diff 可控，与「艺术家页改版」的 `:303-455` 整段替换互不干扰（页内再改内容即可）
- **方式 2**：新建 `lib/screens/library/` 目录，每页独立文件。文件更小可读性更好，但引入 5~6 个新文件

### 4.2 状态同步（v1.2 审查修正：删除 `_selectedFilter`，TabController 即状态源）

```
TabController（State 持有，SingleTickerProviderStateMixin，可空 `TabController?` + `_tabInited` 首帧防护）
  ├─ TabBar / TabBarView 共享同一 controller（点按/滑动由框架双向同步）
  ├─ 页面内容 = 显式 filter 参数（_buildPage(f) → _getFilteredItems(..., f)），
  │     不读 _selectedFilter —— 该字段整体删除（原 :40），_syncSelectedFilter/indexIsChanging 同步逻辑随之消失
  ├─ _getFilters 数量变化（本地模式 4⇄6）→ 显式监听 LibraryProvider：
  │     initState: Provider.of<LibraryProvider>(context, listen: false).addListener(_onLibraryChanged)
  │     _onLibraryChanged: filters.length != _tabController?.length → setState 重建 controller
  │     dispose 注销
  │     ⚠️ 勿依赖 didChangeDependencies：State 层全用 listen:false（:92-93/:363）未注册依赖，
  │        且 setServerOfflineMode 不 notify（library_provider.dart:191-193）
  └─ 重建时 initialIndex = min(旧 index, length-1)，保留当前页
```

- 删除 `_selectedFilter`（`:40`）：唯一引用方是 chips 行（已删）与内容分支（已参数化），无其他消费者
- TabBarView children 加 `KeyedSubtree(key: ValueKey(filter))`，防 filters 顺序变化时按 index 复用错位
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
| TabBarView 横向滑（页面主体区域） | ✅ 框架原生（内部 PageView），页间跟手 + 惯性 |
| TabBar 行横向拖 | ✅ 交给 TabBarView 手势仲裁（标准组合行为）：TabBar 上滑动/点按均切页，与内容页滑动无竞争 |
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

### 5.1 头部样式（已拍板：网易新闻/百度 App 首页式 TabBar）

| 项 | 定案 |
|---|---|
| 形态 | 顶部文字标签 + 下划线指示器（`TabBar`），内容页 `TabBarView` 左右滑动——网易新闻/百度 App 首页交互 |
| 滚动 | `isScrollable: true`（标签按内容宽度排布），兼容 4 tab（服务端）与 6 tab（本地模式）动态数量 |
| 选中态 | 选中 = 主题强调色 + 加粗；未选中 = 次要文字色；指示器 2~3pt 圆角下划线 |
| 文案 | 沿用现有 `filterLabels`（`:180-187`），替换 FilterChip 行（`:188-226`） |

> 布局说明：网易新闻式 TabBar 位于 AppBar 正下方、内容区正上方，三者固定头部结构 `AppBar → TabBar → TabBarView`（内容左右滑动、头部不动）。

### 5.2 切换动画

- TabBarView 自带跟手 + 惯性；Tab 点按切换用 `controller.animateTo`（`Curves.easeOutCubic`，250ms）
- 移除 `AnimatedSwitcher`（`:231`）淡入淡出

### 5.3 底部留白

- 每页底部保留 ~150 留白（现 `:479`），迷你播放器避让不变

---

## 6. 改动文件清单与实施状态

| 文件 | 改动 | 状态 |
|---|---|---|
| `lib/screens/library_screen.dart` | ✅ build 重构（`:181-297`：AppBar `:199` + TabBar `:261` + TabBarView `:286`）；TabController 生命周期 `_ensureTabController:82` / `_onLibraryChanged:98` / `_onTabIndexChanged:106`（initState `:70` 显式监听 LibraryProvider、dispose `:121`，可空 + 首帧防护）；删除 `GestureDetector`/`_swipeDelta`/`AnimatedSwitcher`/FilterChip 行/`_selectedFilter`；每页独立 ScrollController（`:54-59`）；页面拆分 `_buildArtistsPage:331` / `_buildFavesPage:492` / `_buildItemsPage:572` + `_controllerFor:310`；`_getFilteredItems:600` 加 filter 参数、删 Artists 死分支；封面预热改 `_onTabIndexChanged` 触发（`_maybePreloadArtistCovers:1026`） | ✅ 2026-08-06 实施：analyze 无 error；widgets/services 单测全绿，`flutter test` +102 ~5 -3（3 失败经 git stash 验证为改动前已存在：`player_provider_test` 构造签名过期、`app_test` 登录文案断言过期） |
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

| # | 决策点 | 状态 |
|---|---|---|
| 1 | 方案选型 | ✅ 已拍板：A `TabBar + TabBarView`（2026-08-05，样式参照网易新闻/百度 App 首页）；B 作废 |
| 2 | 页面拆分方式 | ✅ 已按推荐实施：**同文件方法化**（`_buildArtistsPage:331` / `_buildFavesPage:492` / `_buildItemsPage:572`，状态留 State，避免跨类回调） |
| 3 | 头部样式 | ✅ 已拍板：文字 TabBar + 下划线指示器（`isScrollable: true`），替换 FilterChip 行 |
| 4 | 小幅横滑回弹 | ✅ 已确认（2026-08-06 真机反馈）：小幅拖动页面跟手移动后松手回弹为 PageView 标准行为（半页+速度阈值，网易新闻/百度 App 同款），**保持现状不改** |
