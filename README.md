# SPlayer-iOS

SPlayer-Next（[SPlayer-Dev/SPlayer-Next](https://github.com/SPlayer-Dev/SPlayer-Next)）的独立 SwiftUI iOS 客户端。

- 目标设备：iPhone SE2（375×667）/ iOS 17+
- 数据层：自建 NeteaseCloudMusicApi Enhanced（局域网 / Tailscale）
- 构建：GitHub Actions 云端产出未签名 IPA，Sideloadly 自签安装
- 主色 `#FE7971`，支持深色模式

## 路线图

- [x] M1 仓库骨架 + CI 构建 + 空 Tab
- [x] M2 QR 扫码登录（Keychain 存储 MUSIC_U）
- [x] M3 歌单列表 / 详情 / 搜索
- [x] M4 播放 + 本地缓存 + 后台/锁屏控制
- [x] M5 歌词滚动 + 设置页
- [x] M6 预载下一曲 / 错误态打磨
- [x] M7 手机号/邮箱验证码登录 + 播放模式 + 桌面歌词小组件 / iPad 适配
- [x] M8 首页发现（每日推荐 / 推荐歌单 / 排行榜）+ 我喜欢的音乐 + 最近播放
- [x] M9 搜索分类（单曲 / 歌手 / 专辑 / 歌单）+ 歌手 / 专辑详情页
- [x] M10 歌曲列表快捷收藏 + 歌曲 / 歌单 / 歌手 / 专辑分享
- [x] M11 关注歌手 / 收藏歌单 / 歌曲评论 / 播放队列拖拽排序
- [x] M12 关注歌手列表 / 歌单内搜索 / 评论点赞与发送 / 首页换一批
- [x] M13 评论分页加载 / 歌单增删歌曲 / 用户主页 / 歌词点击跳转
- [x] M14 私人 FM / 专辑收藏 / 关注与粉丝列表 / 歌单创建管理
- [x] M15 排行榜 / 歌单广场 / 新歌速递 / 新碟上架
- [x] M16 MV 播放 / 听歌排行 / 我的云盘
- [x] M17 倍速播放 / 睡眠定时 / 缓存管理
- [x] M18 逐字歌词（YRC）/ 罗马音 / 歌词偏移
- [x] M19 本地音乐导入 / 元数据解析 / 本地播放
- [x] M20 多服务器：Subsonic / Navidrome、Jellyfin、Emby 配置、浏览与播放
- [x] M21 播客电台（热门电台 / 推荐节目 / 节目详情与播放）、全部歌手
- [x] M22 评论扩展至专辑 / 歌单 / MV、收藏专辑列表
- [x] M23 搜索增强：热搜榜 / 搜索建议 / 搜索历史
- [x] M24 歌手详情增强：歌手介绍、MV 列表
- [x] M25 下载管理：显式下载 / 删除 / 空间统计，播放优先使用下载文件
- [x] M26 云盘上传：本地音频上传到网易云云盘（multipart/form-data）
- [x] M27 私信：最近联系人、会话历史、发送消息
- [x] M28 云村动态：动态流、图片、分享歌曲播放、点赞
- [x] M29 下一首播放、云盘歌曲删除

## 构建

推送即触发 `.github/workflows/ios.yml`（macos-15）：XcodeGen 生成工程 → xcodebuild 未签名构建 → 打包 IPA → Actions Artifact 下载（保留 30 天）。

## 安装（Sideloadly，7 天续签）

1. Windows 安装 Sideloadly 与 Apple Devices 驱动；appleid.apple.com 生成 App 专用密码
2. 下载 Actions Artifact 中的 IPA，拖入 Sideloadly，填 Apple ID 与专用密码
3. Bundle ID 改为唯一值（如 `com.<你的标识>.splayerios`），勾选 Keep app data
4. iPhone 设置 → 通用 → VPN 与设备管理 → 信任开发者证书
5. 每 7 天用同一 Apple ID + 同 Bundle ID 覆盖安装续签（勿卸载，否则 Keychain 登录态丢失）
