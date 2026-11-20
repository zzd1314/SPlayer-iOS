import SwiftUI

@main
struct SPlayerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // 尽早启动内置网易云 API 服务，保证首个请求前端口已就绪
        BuiltinAPIService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            // 休眠唤醒后本地监听可能失效：探活并在必要时重启本地服务
            Task { await BuiltinAPIService.shared.recoverIfNeeded() }
        }
    }
}
