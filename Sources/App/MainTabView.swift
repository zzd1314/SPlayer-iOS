import SwiftUI

/// 主界面：首页 / 资料库 / 搜索 / 设置 四个 Tab + 悬浮胶囊迷你播放条
struct MainTabView: View {
    @EnvironmentObject private var player: PlayerStore

    var body: some View {
        TabView {
            tab(HomeView())
                .tabItem { Label("首页", systemImage: "house.fill") }
            tab(LibraryView())
                .tabItem { Label("资料库", systemImage: "music.note.house.fill") }
            tab(SearchView())
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            tab(SettingsView())
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }

    /// 在每个 Tab 页面内插入迷你播放条，确保它悬浮在底部 Tab 栏之上，
    /// 同时通过 safeAreaInset 为页面内容预留空间，避免遮挡。
    @ViewBuilder
    private func tab<Content: View>(_ content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.currentSong != nil {
                    MiniPlayer()
                        .padding(.horizontal, 14)
                        .padding(.top, 6)
                        .padding(.bottom, 8)
                }
            }
    }
}
