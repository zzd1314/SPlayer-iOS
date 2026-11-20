import SwiftUI

@main
struct SPlayerApp: App {
    init() {
        // 尽早启动内置网易云 API 服务，保证首个请求前端口已就绪
        BuiltinAPIService.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
