import SwiftUI

// MARK: - 分栏

/// 桌面版左侧图标栏对应的主导航分区
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case discover
    case library
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .discover: return "发现"
        case .library: return "资料库"
        case .search: return "搜索"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .discover: return "safari"
        case .library: return "music.note.list"
        case .search: return "magnifyingglass"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .discover: return "safari.fill"
        case .library: return "music.note.list"
        case .search: return "magnifyingglass"
        }
    }
}

// MARK: - 路由

/// 外壳级路由：当前分区、各分区导航栈、全局搜索框与弹窗状态
@MainActor
final class ShellRouter: ObservableObject {
    @Published var section: AppSection = .home
    @Published var homePath = NavigationPath()
    @Published var discoverPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var searchPath = NavigationPath()

    @Published var searchText = ""
    @Published var submittedQuery = ""
    @Published var searchToken = 0
    @Published var focusSearchToken = 0

    @Published var showSettings = false
    @Published var showProfile = false

    /// 每个分区「后退」后保存的历史栈，供顶栏前进箭头使用
    private var forwardStacks: [AppSection: [NavigationPath]] = [:]
    private var isRestoringForward = false

    func path(for section: AppSection) -> NavigationPath {
        switch section {
        case .home: return homePath
        case .discover: return discoverPath
        case .library: return libraryPath
        case .search: return searchPath
        }
    }

    func binding(for section: AppSection) -> Binding<NavigationPath> {
        Binding(
            get: { self.path(for: section) },
            set: { newValue in
                let oldCount = self.path(for: section).count
                if newValue.count > oldCount, !self.isRestoringForward {
                    // 用户产生新的跳转时，丢弃旧的前进历史
                    self.forwardStacks[section] = []
                }
                self.setPath(newValue, for: section)
            }
        )
    }

    var canGoBack: Bool { !path(for: section).isEmpty }
    var canGoForward: Bool { !(forwardStacks[section]?.isEmpty ?? true) }

    func goBack() {
        var current = path(for: section)
        guard !current.isEmpty else { return }
        forwardStacks[section, default: []].append(current)
        current.removeLast()
        setPath(current, for: section)
    }

    func goForward() {
        guard var stack = forwardStacks[section], let next = stack.popLast() else { return }
        forwardStacks[section] = stack
        isRestoringForward = true
        setPath(next, for: section)
        isRestoringForward = false
    }

    func openSearch() {
        section = .search
        focusSearchToken += 1
    }

    func submitSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        submittedQuery = keyword
        searchToken += 1
        section = .search
    }

    private func setPath(_ path: NavigationPath, for section: AppSection) {
        switch section {
        case .home: homePath = path
        case .discover: discoverPath = path
        case .library: libraryPath = path
        case .search: searchPath = path
        }
    }
}

// MARK: - 外壳

/// 桌面版式主界面：左侧图标栏 + 顶部导航栏 + 内容区 + 底部整条播放栏
struct MainShellView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @StateObject private var router = ShellRouter()
    /// 已访问过的分区保持挂载，切换时保留滚动位置与加载结果
    @State private var mountedSections: Set<AppSection> = [.home]

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(spacing: 0) {
            ShellSidebar()
                .frame(width: isRegular ? 58 : 52)

            VStack(spacing: 0) {
                ShellTopBar(isRegular: isRegular)

                ZStack {
                    ForEach(AppSection.allCases) { section in
                        if mountedSections.contains(section) {
                            sectionView(section)
                                .opacity(router.section == section ? 1 : 0)
                                .allowsHitTesting(router.section == section)
                                .accessibilityHidden(router.section != section)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentSong != nil {
                    PlayerBar()
                }
            }
        }
        .environmentObject(router)
        .onChange(of: router.section) { _, newValue in
            mountedSections.insert(newValue)
        }
        .overlay {
            if router.showSettings {
                SettingsOverlay(onClose: { router.showSettings = false })
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: router.showSettings)
        .sheet(isPresented: $router.showProfile) {
            profileSheet
        }
    }

    @ViewBuilder
    private func sectionView(_ section: AppSection) -> some View {
        switch section {
        case .home: HomeView()
        case .discover: DiscoverView()
        case .library: LibraryView()
        case .search: SearchView()
        }
    }

    @ViewBuilder
    private var profileSheet: some View {
        NavigationStack {
            Group {
                if let profile = auth.profile {
                    UserProfileView(userId: profile.userId, nickname: profile.nickname)
                } else {
                    ContentUnavailableView(
                        "未登录",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("登录后可查看个人主页")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { router.showProfile = false }
                }
            }
        }
    }
}

// MARK: - 左侧图标栏

private struct ShellSidebar: View {
    @EnvironmentObject private var router: ShellRouter

    var body: some View {
        VStack(spacing: 4) {
            logo
                .padding(.top, 12)
                .padding(.bottom, 12)

            ForEach(AppSection.allCases) { section in
                sidebarButton(section)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    router.showSettings = true
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
            .accessibilityLabel("设置")
        }
        .frame(maxHeight: .infinity)
        .background {
            Color.primary.opacity(0.045)
                .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(width: 0.5)
                .ignoresSafeArea()
        }
    }

    private var logo: some View {
        Image(systemName: "music.note")
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(Color.splayerAccent)
            .frame(width: 38, height: 38)
            .background(Color.splayerAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sidebarButton(_ section: AppSection) -> some View {
        let isSelected = router.section == section
        return Button {
            if section == .search {
                router.openSearch()
            } else {
                router.section = section
            }
        } label: {
            Image(systemName: isSelected ? section.selectedIcon : section.icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSelected ? Color.splayerAccent : Color.secondary)
                .frame(width: 38, height: 38)
                .background(
                    isSelected ? Color.splayerAccent.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.title)
        .accessibilityLabel(section.title)
    }
}

// MARK: - 顶部导航栏

private struct ShellTopBar: View {
    @EnvironmentObject private var router: ShellRouter
    @EnvironmentObject private var auth: AuthStore
    @AppStorage("themeMode") private var themeMode = "system"
    @FocusState private var searchFocused: Bool

    let isRegular: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isRegular {
                historyButtons
            }

            searchField

            Spacer(minLength: 6)

            themeButton

            userChip
        }
        .padding(.horizontal, isRegular ? 18 : 10)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
        .onChange(of: router.focusSearchToken) { _, _ in
            searchFocused = true
        }
    }

    private var historyButtons: some View {
        HStack(spacing: 2) {
            Button {
                router.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!router.canGoBack)
            .foregroundStyle(router.canGoBack ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.35))
            .accessibilityLabel("后退")

            Button {
                router.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!router.canGoForward)
            .foregroundStyle(router.canGoForward ? Color.primary.opacity(0.75) : Color.secondary.opacity(0.35))
            .accessibilityLabel("前进")
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索歌曲、歌手或专辑", text: $router.searchText)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($searchFocused)
                .onSubmit {
                    router.submitSearch()
                    searchFocused = false
                }

            if !router.searchText.isEmpty {
                Button {
                    router.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .frame(maxWidth: isRegular ? 460 : .infinity)
    }

    private var themeButton: some View {
        Button {
            switch themeMode {
            case "light": themeMode = "dark"
            case "dark": themeMode = "system"
            default: themeMode = "light"
            }
        } label: {
            Image(systemName: themeIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("切换主题")
    }

    private var themeIcon: String {
        switch themeMode {
        case "light": return "sun.max.fill"
        case "dark": return "moon.fill"
        default: return "circle.lefthalf.filled"
        }
    }

    private var userChip: some View {
        Button {
            router.showProfile = true
        } label: {
            HStack(spacing: 7) {
                CoverImage(urlString: auth.profile?.avatarUrl, size: 26, cornerRadius: 13)

                if isRegular {
                    Text(auth.profile?.nickname ?? "未登录")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 3)
            .padding(.trailing, isRegular ? 8 : 3)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("个人主页")
    }
}

// MARK: - 设置弹窗容器

private struct SettingsOverlay: View {
    let onClose: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            SettingsView(onClose: onClose)
                .frame(
                    maxWidth: isRegular ? 1020 : .infinity,
                    maxHeight: isRegular ? 680 : .infinity
                )
                .padding(isRegular ? 32 : 8)
                .shadow(color: .black.opacity(0.35), radius: 40, y: 18)
        }
    }
}
