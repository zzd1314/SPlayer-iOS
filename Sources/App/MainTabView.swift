import SwiftUI

/// 主界面：资料库 / 搜索 / 设置 三个 Tab（播放页后续以 MiniPlayer + 全屏覆盖层呈现）
struct MainTabView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("资料库", systemImage: "music.note.house.fill") }
            SearchView()
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}
