import SwiftUI

/// 根视图：未登录显示登录页，已登录进入主界面
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthStore()
    @StateObject private var player = PlayerStore()

    @AppStorage("themeMode") private var themeMode = "system"
    @AppStorage("themeSource") private var themeSource = "default"
    @AppStorage("customThemeColor") private var customThemeColor = "FE7971"

    private var colorScheme: ColorScheme? {
        switch themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var tintColor: Color {
        switch themeSource {
        case "custom":
            return Color(hexString: customThemeColor) ?? .splayerAccent
        case "cover":
            return player.coverAccent ?? .splayerAccent
        case "solid":
            return .primary
        default:
            return .splayerAccent
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            Group {
                if auth.isLoggedIn {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
        }
        .environmentObject(auth)
        .environmentObject(player)
        .tint(tintColor)
        .preferredColorScheme(colorScheme)
        .task {
            player.cookie = auth.cookie
            guard auth.isLoggedIn else {
                await player.applyAccount(userID: nil)
                return
            }
            await auth.refreshProfile()
            player.cookie = auth.cookie
            await player.applyAccount(userID: auth.profile?.userId)
            await player.restoreIfNeeded()
        }
        .onChange(of: auth.cookie) { _, newValue in
            player.cookie = newValue
            guard newValue != nil else {
                Task { await player.applyAccount(userID: nil) }
                return
            }
            Task {
                await auth.refreshProfile()
                player.cookie = auth.cookie
                await player.applyAccount(userID: auth.profile?.userId)
                await player.restoreIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await auth.refreshProfile() }
            case .background:
                player.persistPlaybackState()
                player.syncNowPlaying()
            default:
                break
            }
        }
    }
}
