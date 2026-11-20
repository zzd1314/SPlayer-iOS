import PhotosUI
import SwiftUI
import UIKit

// MARK: - 设置分类

/// 设置分类（顺序对齐桌面版设置弹窗左侧菜单）
private enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general
    case playback
    case lyrics
    case appearance
    case service
    case servers
    case cache
    case download
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "常规设置"
        case .playback: return "播放设置"
        case .lyrics: return "歌词设置"
        case .appearance: return "外观设置"
        case .service: return "网络与服务"
        case .servers: return "媒体服务器"
        case .cache: return "本地与缓存"
        case .download: return "下载管理"
        case .about: return "关于软件"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "自动播放、记忆播放进度、播放栏歌词"
        case .playback: return "音质、预载、屏幕常亮、时间格式"
        case .lyrics: return "翻译、字号、对齐、颜色、锁屏歌词"
        case .appearance: return "主题模式、主题色、背景风格"
        case .service: return "平台登录、API 服务器"
        case .servers: return "Subsonic / Navidrome / Jellyfin / Emby"
        case .cache: return "歌曲缓存、缓存上限、清理"
        case .download: return "已下载歌曲与空间占用"
        case .about: return "版本信息、重置设置"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .playback: return "play.circle.fill"
        case .lyrics: return "text.quote"
        case .appearance: return "paintbrush.fill"
        case .service: return "network"
        case .servers: return "externaldrive.connected.to.line.below"
        case .cache: return "internaldrive.fill"
        case .download: return "arrow.down.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .playback: return .splayerAccent
        case .lyrics: return .pink
        case .appearance: return .purple
        case .service: return .blue
        case .servers: return .indigo
        case .cache: return .green
        case .download: return .teal
        case .about: return .gray
        }
    }
}

// MARK: - 设置弹窗

/// 桌面版式设置弹窗：宽屏双栏（左侧分类 / 右侧内容），窄屏单栏导航
struct SettingsView: View {
    let onClose: () -> Void

    @State private var selection: SettingsCategory = .general

    var body: some View {
        GeometryReader { geo in
            Group {
                if geo.size.width >= 720 {
                    wideLayout
                } else {
                    compactLayout
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
        }
    }

    // MARK: 宽屏双栏

    private var wideLayout: some View {
        HStack(spacing: 0) {
            SettingsMenu(selection: $selection, onClose: onClose)
                .frame(width: 238)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5)

            VStack(alignment: .leading, spacing: 0) {
                // 详情页内部可能还有跳转（如媒体服务器编辑），需要保留导航上下文
                NavigationStack {
                    VStack(alignment: .leading, spacing: 0) {
                        detailHeader
                        detailView(selection)
                            .scrollContentBackground(.hidden)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
                .id(selection)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: selection.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(selection.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title)
                    .font(.title3.weight(.semibold))
                Text(selection.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    // MARK: 窄屏单栏

    private var compactLayout: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SettingsCategory.allCases) { category in
                        NavigationLink(value: category) {
                            SettingsMenuRow(category: category, showsSubtitle: true)
                        }
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
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsCategory.self) { category in
                detailView(category)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onClose)
                }
            }
        }
    }

    // MARK: 内容

    @ViewBuilder
    private func detailView(_ category: SettingsCategory) -> some View {
        switch category {
        case .general: GeneralSettingsView()
        case .playback: PlayerSettingsView()
        case .lyrics: LyricSettingsView()
        case .appearance: AppearanceSettingsView()
        case .service: ServiceSettingsView()
        case .servers: MediaServerListView()
        case .cache: CacheSettingsView()
        case .download: DownloadManageView()
        case .about: AboutSettingsView()
        }
    }
}

// MARK: - 左侧分类菜单

private struct SettingsMenu: View {
    @Binding var selection: SettingsCategory
    let onClose: () -> Void

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(short)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("设置")
                        .font(.title2.weight(.bold))
                    Text("调整您的专属配置")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭设置")
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsCategory.allCases) { category in
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                selection = category
                            }
                        } label: {
                            SettingsMenuRow(category: category, isSelected: selection == category)
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(
                                    selection == category ? Color.primary.opacity(0.06) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("SPlayer-Next iOS")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(versionText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}

private struct SettingsMenuRow: View {
    let category: SettingsCategory
    var isSelected = false
    var showsSubtitle = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.splayerAccent : category.color)
                .frame(width: 26, height: 26)
                .background(
                    (isSelected ? Color.splayerAccent : category.color).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.splayerAccent : Color.primary)
                    .lineLimit(1)

                if showsSubtitle {
                    Text(category.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, showsSubtitle ? 2 : 0)
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
    @ObservedObject private var updater = UpdateChecker.shared

    @AppStorage("updateChannel") private var updateChannel = "stable"
    @AppStorage("autoCheckUpdate") private var autoCheckUpdate = true

    @State private var showResetConfirm = false
    @State private var copied = false

    private let developers: [Developer] = [
        Developer(name: "imsyy", role: "Author"),
        Developer(name: "MoYingJi", role: "Contributor"),
        Developer(name: "kyv001", role: "Contributor"),
        Developer(name: "PhantomPixel-0418", role: "Contributor"),
        Developer(name: "laoshuaikaixue", role: "Contributor"),
        Developer(name: "apoint123", role: "Contributor")
    ]

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var appVersion: String { "\(shortVersion) (\(buildVersion))" }

    private var repoURL: URL {
        URL(string: "https://github.com/SPlayer-Dev/SPlayer-Next")!
    }

    private var contributorsURL: URL {
        URL(string: "https://github.com/zzd1314/SPlayer-iOS/graphs/contributors")!
    }

    private var environmentItems: [EnvironmentItem] {
        [
            EnvironmentItem(title: "应用", value: "SPlayer-Next"),
            EnvironmentItem(title: "版本", value: appVersion),
            EnvironmentItem(title: "系统", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"),
            EnvironmentItem(title: "设备", value: UIDevice.current.localizedModel),
            EnvironmentItem(title: "API", value: AppSettings.useBuiltinAPI ? "内置本地服务" : AppSettings.baseURL),
            EnvironmentItem(title: "界面", value: "SwiftUI")
        ]
    }

    private var environmentText: String {
        environmentItems.map { "\($0.title)：\($0.value)" }.joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("SPlayer-Next")
                            .font(.headline)
                        Text("v\(shortVersion)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)

                Button {
                    Task { await updater.check(manual: true) }
                } label: {
                    HStack {
                        Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
                        Spacer(minLength: 8)
                        if updater.state == .checking {
                            ProgressView()
                        } else if updater.hasUpdate, let release = updater.latestRelease {
                            Text("发现 v\(release.version)")
                                .font(.footnote)
                                .foregroundStyle(Color.splayerAccent)
                        }
                    }
                }
                .disabled(updater.state == .checking)

                if updater.hasUpdate, let release = updater.latestRelease {
                    Button {
                        updater.presentedRelease = release
                    } label: {
                        LabeledContent {
                            Text("v\(release.version)")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("查看新版本", systemImage: "sparkles")
                        }
                    }
                }
            } header: {
                Text("关于软件")
            }

            Section {
                Picker("更新通道", selection: $updateChannel) {
                    Text("正式版").tag("stable")
                    Text("测试版").tag("beta")
                }
                .pickerStyle(.menu)

                Toggle("自动检查更新", isOn: $autoCheckUpdate)
            } header: {
                Text("更新")
            } footer: {
                Text("选择接收更新的通道，切换通道不会自动降级；自动检查会在启动后及定时在后台检查新版本。")
            }

            Section("特别致谢") {
                Link(destination: URL(string: "https://github.com/Steve-xmh/applemusic-like-lyrics")!) {
                    thanksRow(
                        title: "applemusic-like-lyrics",
                        subtitle: "类 Apple Music 歌词显示组件库"
                    )
                }

                Link(destination: URL(string: "https://github.com/neteasecloudmusicapienhanced/api-enhanced")!) {
                    thanksRow(
                        title: "NeteaseCloudMusicApi Enhanced",
                        subtitle: "NCM API 备份 + 增强"
                    )
                }
            }

            Section("开发人员") {
                ForEach(developers) { developer in
                    Link(destination: developer.url) {
                        HStack(spacing: 12) {
                            DeveloperAvatar(name: developer.name)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(developer.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(developer.role)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Link(destination: contributorsURL) {
                    Label("更多贡献者", systemImage: "person.3")
                }
            }

            Section("社区与资讯") {
                Link(destination: repoURL) {
                    Label("SPlayer-Next", systemImage: "chevron.left.forwardslash.chevron.right")
                }

                Link(destination: URL(string: "https://splayer-next.imsyy.top")!) {
                    Label("官方网站", systemImage: "globe")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(environmentItems) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Text(item.title)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(item.value)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .font(.system(.caption, design: .monospaced))
                    }
                }
                .padding(.vertical, 2)

                Button {
                    copyEnvironment()
                } label: {
                    Label(copied ? "已复制" : "复制环境信息", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            } header: {
                Text("环境信息")
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
        .onChange(of: updateChannel) { _, _ in
            Task { await updater.check(manual: false) }
        }
        .sheet(item: $updater.presentedRelease) { release in
            UpdateReleaseView(release: release)
        }
        .alert("检查更新", isPresented: updateAlertBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(updater.alertMessage ?? "")
        }
        .confirmationDialog("重置全部设置？", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("重置", role: .destructive) {
                AppSettings.resetAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("设置将恢复默认值，操作不可撤销。")
        }
    }

    private func thanksRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.splayerAccent)
                .frame(width: 30, height: 30)
                .background(Color.splayerAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func copyEnvironment() {
        UIPasteboard.general.string = environmentText
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    @MainActor
    private var updateAlertBinding: Binding<Bool> {
        Binding(
            get: { updater.alertMessage != nil },
            set: { if !$0 { updater.alertMessage = nil } }
        )
    }
}

// MARK: - 更新说明

/// 新版本说明弹窗：版本信息、更新内容与未签名 IPA 安装提示
private struct UpdateReleaseView: View {
    let release: AppRelease

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var noteLines: [String] {
        guard let body = release.body else { return [] }
        return body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var publishedText: String? {
        guard let date = release.publishedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    notesSection
                    installHint
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("发现新版本")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("SPlayer-Next v\(release.version)")
                    .font(.headline)

                HStack(spacing: 8) {
                    if release.prerelease {
                        Text("测试版")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                    if let publishedText {
                        Text(publishedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("更新内容")
                .font(.headline)

            if noteLines.isEmpty {
                Text("该版本未提供更新说明。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(noteLines.indices, id: \.self) { index in
                        Text(noteLines[index])
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }

    private var installHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text("iOS 无法在应用内直接安装更新。请下载未签名 IPA 后，使用 Sideloadly 或 AltStore 重新签名覆盖安装，账号与本地数据会保留。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            Color.splayerAccent.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            Button {
                openURL(release.ipaURL ?? release.htmlURL)
            } label: {
                Label(
                    release.ipaURL == nil ? "打开发布页" : "下载未签名 IPA",
                    systemImage: release.ipaURL == nil ? "safari" : "arrow.down.circle"
                )
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if release.ipaURL != nil {
                Button("打开发布页") {
                    openURL(release.htmlURL)
                }
                .font(.footnote)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

private struct Developer: Identifiable {
    let name: String
    let role: String
    var id: String { name }
    var url: URL { URL(string: "https://github.com/\(name)")! }
}

private struct DeveloperAvatar: View {
    let name: String

    var body: some View {
        AsyncImage(url: URL(string: "https://github.com/\(name).png?size=96")) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(Circle())
    }
}

private struct EnvironmentItem: Identifiable {
    let title: String
    let value: String
    var id: String { title }
}
