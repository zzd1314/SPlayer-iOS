import SwiftUI

/// 根视图：未登录显示扫码登录，已登录进入主界面
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthStore()
    @StateObject private var player = PlayerStore()

    var body: some View {
        Group {
            if auth.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .environmentObject(auth)
        .environmentObject(player)
        .tint(.splayerAccent)
        .task {
            player.cookie = auth.cookie
            await auth.refreshProfile()
        }
        .onChange(of: auth.cookie) { _, newValue in
            player.cookie = newValue
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await auth.refreshProfile() }
            }
        }
    }
}
