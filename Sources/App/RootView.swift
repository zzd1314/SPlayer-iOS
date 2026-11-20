import SwiftUI

/// 根视图：未登录显示扫码登录，已登录进入主界面
struct RootView: View {
    @StateObject private var auth = AuthStore()

    var body: some View {
        Group {
            if auth.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .environmentObject(auth)
        .tint(.splayerAccent)
        .task {
            await auth.refreshProfile()
        }
    }
}
