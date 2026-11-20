import SwiftUI

/// 设置：M5 实现服务器地址 / 音质 / 缓存管理
struct SettingsView: View {
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("服务器") {
                    LabeledContent("API 地址", value: "未配置（M5 实现）")
                }
                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("阶段", value: "M1 骨架")
                }
            }
            .navigationTitle("设置")
        }
    }
}
