# Luobo - Navidrome 音乐客户端

**Luobo**（萝卜）是一个基于 [Musly](https://github.com/dddevid/Musly) 二次开发的 Navidrome / Subsonic 音乐播放客户端，使用 Flutter 构建，支持 Android 和 iOS。

## 相比原版的改动

- 完整的中文翻译（补全全部缺失的 168 个翻译条目）
- 播放页移除底部音量滑动条（使用系统物理按键调节）
- 歌词入口从顶部 header 移到歌名旁边，操作更顺手
- 设置页硬编码英文改为国际化（如无缝播放、自定义正在播放界面等）

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

## 运行

```bash
flutter pub get
flutter run
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
git fetch upstream
git merge upstream/master
```

## 许可证

本项目遵循 **CC BY-NC-SA 4.0** 许可证，不可用于商业分发。详见 [LICENSE](LICENSE)。
