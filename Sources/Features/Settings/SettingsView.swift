import PhotosUI
import SwiftUI

/// 设置（分组顺序与 SPlayer-Next 桌面版一致）
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        SettingsGroupRow(
                            icon: "gearshape.fill",
                            color: .gray,
                            title: "常规设置",
                            subtitle: "自动播放、记忆播放进度、播放栏歌词"
                        )
                    }

                    NavigationLink {
                        PlayerSettingsView()
                    } label: {
                        SettingsGroupRow(
                            icon: "play.circle.fill",
                            color: .splayerAccent,
                            title: "播放设置",
                            subtitle: "音质、预载、屏幕常亮、时间格式"
                        )
                    }

                    NavigationLink {
                        LyricSettingsView()
                    } label: {
                        SettingsGroupRow(
                            icon: "text.quote",
                            color: .pink,
                            title: "歌词设置",
                            subtitle: "翻译、字号、对齐、颜色、锁屏歌词"
                        )
                    }

                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsGroupRow(
                            icon: "paintbrush.fill",
                            color: .purple,
                            title: "外观设置",
                            subtitle: "主题模式、主题色、背景风格"
                        )
                    }

                    NavigationLink {
                        ServiceSettingsView()
                    } label: {
                        SettingsGroupRow(
                            icon: "network",
                            color: .blue,
                            title: "网络与服务",
                            subtitle: "平台登录、API 服务器"
                        )
                    }

                    NavigationLink {
                        MediaServerListView()
                    } label: {
                        SettingsGroupRow(
                            icon: "externaldrive.connected.to.line.below",
                            color: .indigo,
                            title: "媒体服务器",
                            subtitle: "Subsonic / Navidrome / Jellyfin / Emby"
                        )
                    }

                    NavigationLink {
                        CacheSettingsView()
                    } label: {
                        SettingsGroupRow(
                            icon: "internaldrive.fill",
                            color: .green,
                            title: "本地与缓存",
                            subtitle: "歌曲缓存、缓存上限、清理"
                        )
                    }

                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        SettingsGroupRow(
                            icon: "info.circle.fill",
                            color: .gray,
                            title: "关于软件",
                            subtitle: "版本信息、重置设置"
                        )
                    }
                } header: {
                    Text("调整您的专属配置")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            .adaptiveListBackground()
            .navigationTitle("设置")
        }
    }
}

private struct SettingsGroupRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 常规设置

private struct GeneralSettingsView: View {
    @AppStorage("autoPlay") private var autoPlay = true
    @AppStorage("rememberLastTrack") private var rememberLastTrack = true
    @AppStorage("showLyricInBar") private var showLyricInBar = true
    @AppStorage("searchPlayBehavior") private var searchPlayBehavior = "all"
    @AppStorage("songListPlayBehavior") private var songListPlayBehavior = "all"

    var body: some View {
        Form {
            Section {
                Toggle("自动播放", isOn: $autoPlay)
                Toggle("记忆播放进度", isOn: $rememberLastTrack)
                Toggle("播放时显示歌词", isOn: $showLyricInBar)
            } footer: {
                Text("记忆播放进度：启动时恢复上次歌曲与进度；播放时显示歌词：底部播放栏会把歌手名替换为当前歌词。")
            }

            Section("列表播放行为") {
                Picker("搜索页播放", selection: $searchPlayBehavior) {
                    Text("播放全部").tag("all")
                    Text("仅播放当前").tag("current")
                }
                Picker("歌曲播放按钮行为", selection: $songListPlayBehavior) {
                    Text("播放全部").tag("all")
                    Text("仅播放当前").tag("current")
                }
            }
        }
        .adaptiveListBackground()
        .navigationTitle("常规设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 播放设置

private struct PlayerSettingsView: View {
    @EnvironmentObject private var player: PlayerStore

    @AppStorage("audioLevel") private var audioLevel = "exhigh"
    @AppStorage("preloadNextTrack") private var preloadNextTrack = false
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("timeFormat") private var timeFormat = TimeFormatMode.currentTotal.rawValue

    private var playbackRateBinding: Binding<Double> {
        Binding(
            get: { Double(player.playbackRate) },
            set: { player.setPlaybackRate(Float($0)) }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("在线歌曲音质", selection: $audioLevel) {
                    ForEach(AppSettings.audioLevels, id: \.value) { item in
                        Text(item.label).tag(item.value)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("在线歌曲音质")
            } footer: {
                Text("实际可用级别取决于账号权限与歌曲版权。")
            }

            Section {
                Toggle("预载下一首歌曲", isOn: $preloadNextTrack)
                Toggle("播放时保持屏幕常亮", isOn: $keepScreenAwake)
            } footer: {
                Text("预载会提前缓存下一曲，需要保持「歌曲缓存」开启；屏幕常亮仅在播放页展开且正在播放时生效。")
            }

            Section {
                Picker("播放速度", selection: playbackRateBinding) {
                    ForEach(AppSettings.playbackRateOptions, id: \.self) { value in
                        Text(AppSettings.playbackRateLabel(value)).tag(value)
                    }
                }
            } header: {
                Text("播放速度")
            } footer: {
                Text("可在播放页的倍速按钮中快速切换；设置对当前播放立即生效。")
            }

            Section("时间显示") {
                Picker("时间显示格式", selection: $timeFormat) {
                    ForEach(TimeFormatMode.allCases) { item in
                        Text(item.title).tag(item.rawValue)
                    }
                }
            }
        }
        .adaptiveListBackground()
        .navigationTitle("播放设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 歌词设置

private struct LyricSettingsView: View {
    @AppStorage("showTranslation") private var showTranslation = true
    @AppStorage("showRomanization") private var showRomanization = false
    @AppStorage("lyricOffset") private var lyricOffset = 0.0
    @AppStorage("lyricFontSize") private var lyricFontSize = 22.0
    @AppStorage("lyricAlignment") private var lyricAlignment = "auto"
    @AppStorage("inactiveAlpha") private var inactiveAlpha = 0.45
    @AppStorage("followCoverColor") private var followCoverColor = true
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true

    var body: some View {
        Form {
            Section {
                Toggle("显示翻译", isOn: $showTranslation)
                Toggle("显示罗马音", isOn: $showRomanization)
                Toggle("跟随封面颜色", isOn: $followCoverColor)
            } header: {
                Text("内容")
            } footer: {
                Text("跟随封面颜色会提取当前封面主色，用于歌词高亮与主题色；逐字歌词会按演唱进度逐字高亮。")
            }

            Section("样式") {
                HStack {
                    Text("歌词字号")
                    Slider(value: $lyricFontSize, in: 14...36, step: 1)
                    Text("\(Int(lyricFontSize))")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                }

                Picker("歌词水平对齐", selection: $lyricAlignment) {
                    Text("自动").tag("auto")
                    Text("靠左").tag("left")
                    Text("居中").tag("center")
                    Text("靠右").tag("right")
                }

                HStack {
                    Text("非激活行透明度")
                    Slider(value: $inactiveAlpha, in: 0.1...1, step: 0.05)
                    Text("\(Int(inactiveAlpha * 100))%")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
            }

            Section {
                HStack {
                    Text("歌词偏移")
                    Slider(value: $lyricOffset, in: -3...3, step: 0.1)
                    Text(String(format: "%+.1f 秒", lyricOffset))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            } header: {
                Text("时间轴")
            } footer: {
                Text("正值让歌词提前显示，负值延后显示，用于校正歌词与音频的时间差。")
            }

            Section {
                Toggle("灵动岛 / 锁屏歌词", isOn: $liveActivityEnabled)
            } footer: {
                Text("iOS 上「桌面歌词」由灵动岛与锁屏 Live Activity 呈现，播放时会随歌词行更新。桌面小组件在添加后显示当前歌词；受系统刷新策略限制，桌面小组件不会逐行实时滚动。")
            }
        }
        .adaptiveListBackground()
        .navigationTitle("歌词设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 外观设置

private struct AppearanceSettingsView: View {
    @AppStorage("themeMode") private var themeMode = "system"
    @AppStorage("themeSource") private var themeSource = "default"
    @AppStorage("customThemeColor") private var customThemeColor = "FE7971"
    @AppStorage("appearanceStyle") private var appearanceStyle = "solid"
    @AppStorage("backgroundBlur") private var backgroundBlur = 20.0
    @AppStorage("backgroundDim") private var backgroundDim = 0.32
    @AppStorage("backgroundRevision") private var backgroundRevision = 0

    @State private var pickedItem: PhotosPickerItem?

    private let themeSources: [(String, String)] = [
        ("default", "默认主题色"),
        ("custom", "自定义主色"),
        ("cover", "跟随封面 / 背景"),
        ("solid", "无主题色")
    ]

    private var customColorBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: customThemeColor) ?? .splayerAccent },
            set: { customThemeColor = $0.hexString ?? "FE7971" }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("主题模式", selection: $themeMode) {
                    Text("跟随系统").tag("system")
                    Text("浅色模式").tag("light")
                    Text("深色模式").tag("dark")
                }
            }

            Section {
                Picker("主题色来源", selection: $themeSource) {
                    ForEach(themeSources, id: \.0) { item in
                        Text(item.1).tag(item.0)
                    }
                }
                if themeSource == "custom" {
                    ColorPicker("自定义主题色", selection: customColorBinding, supportsOpacity: false)
                }
            } header: {
                Text("主题与颜色")
            } footer: {
                Text("跟随封面会在播放时提取封面主色作为全局强调色。")
            }

            Section {
                Picker("外观风格", selection: $appearanceStyle) {
                    Text("纯色背景").tag("solid")
                    Text("自定义图片").tag("image")
                }
                .pickerStyle(.segmented)

                if appearanceStyle == "image" {
                    HStack(spacing: 12) {
                        if let image = BackgroundImageStore.load() {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        PhotosPicker(selection: $pickedItem, matching: .images) {
                            Label(
                                BackgroundImageStore.load() == nil ? "选择图片" : "更换图片",
                                systemImage: "photo"
                            )
                            .font(.subheadline)
                        }

                        Spacer()

                        Button("清除", role: .destructive) {
                            BackgroundImageStore.clear()
                            backgroundRevision += 1
                            appearanceStyle = "solid"
                        }
                    }

                    HStack {
                        Text("背景模糊")
                        Slider(value: $backgroundBlur, in: 0...60, step: 1)
                        Text("\(Int(backgroundBlur))")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 26, alignment: .trailing)
                    }

                    HStack {
                        Text("遮罩浓度")
                        Slider(value: $backgroundDim, in: 0...0.8, step: 0.02)
                        Text("\(Int(backgroundDim * 100))%")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            } header: {
                Text("外观风格")
            } footer: {
                Text("选择图片作为应用背景，可叠加高斯模糊与暗色遮罩以提升文字可读性。")
            }
        }
        .adaptiveListBackground()
        .navigationTitle("外观设置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self),
                   BackgroundImageStore.save(data) {
                    backgroundRevision += 1
                    appearanceStyle = "image"
                }
                pickedItem = nil
            }
        }
    }
}

// MARK: - 网络与服务

private struct ServiceSettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @AppStorage("apiBaseURL") private var apiBaseURL = AppSettings.defaultBaseURL

    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded: Bool?
    @State private var showLogoutConfirm = false

    var body: some View {
        Form {
            Section("平台登录") {
                if let profile = auth.profile {
                    HStack(spacing: 12) {
                        CoverImage(urlString: profile.avatarUrl, size: 48, cornerRadius: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.nickname)
                                .font(.headline)
                            Text("UID \(profile.userId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                } else {
                    LabeledContent(
                        "状态",
                        value: auth.isLoadingProfile ? "正在获取资料…" : (auth.isLoggedIn ? "已登录" : "未登录")
                    )
                }

                if let error = auth.profileError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button("退出登录", role: .destructive) {
                    showLogoutConfirm = true
                }
            }

            Section {
                NavigationLink {
                    ServerSettingsView()
                } label: {
                    LabeledContent("API 服务器", value: apiBaseURL)
                }

                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        } else if let testMessage {
                            Text(testMessage)
                                .font(.footnote)
                                .foregroundStyle(testSucceeded == true ? Color.green : Color.red)
                        }
                    }
                }
                .disabled(isTesting)
            } header: {
                Text("服务器")
            } footer: {
                Text("填写自建 NeteaseCloudMusicApi Enhanced 地址；手机需与服务器处于同一网络，或已配置 Tailscale。")
            }
        }
        .adaptiveListBackground()
        .navigationTitle("网络与服务")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("退出当前账号？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                auth.signOut()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func testConnection() async {
        isTesting = true
        testMessage = nil
        testSucceeded = nil
        defer { isTesting = false }

        do {
            _ = try await NeteaseAPI().qrKey()
            testSucceeded = true
            testMessage = "连接正常"
        } catch {
            testSucceeded = false
            testMessage = "连接失败"
        }
    }
}

// MARK: - 本地与缓存

private struct CacheSettingsView: View {
    @AppStorage("enableSongCache") private var enableSongCache = true
    @AppStorage("cacheLimitMB") private var cacheLimitMB = 1024

    @State private var cacheSize: Int64 = 0
    @State private var showClearConfirm = false

    private var cacheText: String {
        cacheSize == 0 ? "0 MB" : ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    var body: some View {
        Form {
            Section {
                Toggle("歌曲缓存", isOn: $enableSongCache)
                Picker("缓存上限", selection: $cacheLimitMB) {
                    ForEach(AppSettings.cacheLimitOptions, id: \.self) { value in
                        Text(AppSettings.cacheLimitLabel(value)).tag(value)
                    }
                }
                LabeledContent("当前占用", value: cacheText)
            } footer: {
                Text("播放在线歌曲时缓存到本地；达到上限后会自动清理最早使用的缓存。")
            }

            Section {
                NavigationLink {
                    CacheManageView()
                } label: {
                    Label("缓存管理", systemImage: "music.note.list")
                }

                Button("清除缓存", role: .destructive) {
                    showClearConfirm = true
                }
                .disabled(cacheSize == 0)
            }
        }
        .adaptiveListBackground()
        .navigationTitle("本地与缓存")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            cacheSize = AudioCache.totalSize()
        }
        .confirmationDialog("清除全部歌曲缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                AudioCache.clear()
                cacheSize = AudioCache.totalSize()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("下次播放时会重新下载，操作不可恢复。")
        }
    }
}

// MARK: - 关于

private struct AboutSettingsView: View {
    @State private var showResetConfirm = false

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("应用", value: "SPlayer-Next")
                LabeledContent("平台", value: "iOS / iPadOS")
                LabeledContent("版本", value: appVersion)
            }

            Section {
                Button("重置设置", role: .destructive) {
                    showResetConfirm = true
                }
            } footer: {
                Text("将全部设置项还原为默认值，不影响登录状态、歌单与已缓存文件。")
            }
        }
        .adaptiveListBackground()
        .navigationTitle("关于软件")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("重置全部设置？", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("重置", role: .destructive) {
                AppSettings.resetAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("设置将恢复默认值，操作不可撤销。")
        }
    }
}
