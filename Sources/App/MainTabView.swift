import SwiftUI

/// 主界面：资料库 / 搜索 / 设置 三个 Tab + 底部迷你播放条
struct MainTabView: View {
    @EnvironmentObject private var player: PlayerStore

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("资料库", systemImage: "music.note.house.fill") }
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if player.currentSong != nil {
                MiniPlayer()
            }
        }
    }
}
