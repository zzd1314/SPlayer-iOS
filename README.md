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
- [ ] M6 预载下一曲 / 错误态打磨

## 构建

推送即触发 `.github/workflows/ios.yml`（macos-15）：XcodeGen 生成工程 → xcodebuild 未签名构建 → 打包 IPA → Actions Artifact 下载（保留 30 天）。

## 安装（Sideloadly，7 天续签）

1. Windows 安装 Sideloadly 与 Apple Devices 驱动；appleid.apple.com 生成 App 专用密码
2. 下载 Actions Artifact 中的 IPA，拖入 Sideloadly，填 Apple ID 与专用密码
3. Bundle ID 改为唯一值（如 `com.<你的标识>.splayerios`），勾选 Keep app data
4. iPhone 设置 → 通用 → VPN 与设备管理 → 信任开发者证书
5. 每 7 天用同一 Apple ID + 同 Bundle ID 覆盖安装续签（勿卸载，否则 Keychain 登录态丢失）
