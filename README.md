# Luobo - Navidrome 音乐客户端

**Luobo**（萝卜）是一个基于 [Musly](https://github.com/dddevid/Musly) 二次开发的 Navidrome / Subsonic 音乐播放客户端，使用 Flutter 构建，支持 Android 和 iOS。

## 相比原版的改动

### 新功能

- **车载模式** — 大字歌词（3行实时同步）、播放进度圆环、屏幕常亮、下滑手势返回
- **听歌报告** — 完整的听歌数据分析：
  - 概览统计（总时长/播放次数/歌手数/歌曲数）
  - 完播率与个性化评语
  - 时段偏好（什么时间听什么类型/歌手）
  - Top 歌曲 / 歌手排行
  - 跳过榜（你最常跳过的歌）
  - 单曲循环记录
  - 流派分布（自动中英文归一化）
  - 新发现（最近突然爱上的歌）
  - 老朋友（一直陪伴你的歌手）
  - 周末 vs 工作日对比
  - 能量曲线（各时段节奏能量）
  - 歌荒预警
- **AI 歌单** — 设置页新增独立「AI 歌单」Tab（从播放设置中拆出）：
  - AI 连接配置（API Key / Base URL / 模型，兼容 DeepSeek、OpenAI、Kimi、通义等）
  - 歌曲知识库生成（批量处理、断点续传、增量更新）
  - 知识库导出 / 导入（JSON 文件，多人共用同一 NAS 曲库时可复用，节省 API 调用）
  - AI 歌单 / 知识库生成原理说明

### UI 优化

- 完整中文翻译（补全 168 个缺失条目 + 15 个未翻译条目）
- 播放页移除底部音量滑动条
- 歌词入口从顶部 header 移到歌名旁边（歌词 / 车载 / + / ♡）
- Android edge-to-edge 适配（底部手势条透明）
- 设置页硬编码英文改为国际化
- 流派显示统一为中文（Pop→流行、Rock→摇滚 等）
- 大规模国际化补全（28 种语言）：歌单管理（多选移除/重新排序/下载）、全部歌曲排序菜单、收藏、电台、登录错误分类提示、主题编辑器、自定义组件等界面硬编码英文全部替换为翻译条目

### Bug 修复

- 修复创建歌单弹窗取消/确认后崩溃问题
- 修复专辑卡片在网格列表中底部溢出 1px 的布局问题

## 功能

- 支持 Navidrome / Subsonic / Airsonic / Gonic 服务器
- Apple Music 风格界面
- 同步歌词显示
- 离线下载
- Android Auto 支持
- 随机播放 & 循环播放
- 播放队列管理
- 暗色/亮色主题自动切换
- 智能推荐与个性化混音
- 网络电台

## 运行

```bash
flutter pub get
flutter run
```

构建 release APK（arm64）：

```bash
flutter build apk --release --target-platform android-arm64
```

## 连接服务器

1. 启动应用
2. 输入服务器地址（如 `https://your-server.com`）
3. 输入用户名和密码
4. 如果使用旧版服务器，开启"旧版认证"
5. 点击"连接"

## 上游同步

本项目 fork 自 [dddevid/Musly](https://github.com/dddevid/Musly)，可随时同步上游更新：

```bash
git remote add upstream https://github.com/dddevid/Musly.git
git fetch upstream
git merge upstream/master
```

## 许可证

本项目遵循 **CC BY-NC-SA 4.0** 许可证，不可用于商业分发。详见 [LICENSE](LICENSE)。
