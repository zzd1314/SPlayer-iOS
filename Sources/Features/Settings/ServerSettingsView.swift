import SwiftUI

/// 服务器地址设置（登录页 / 设置页共用）
struct ServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("apiBaseURL") private var apiBaseURL: String = AppSettings.defaultBaseURL

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppSettings.defaultBaseURL, text: $apiBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } footer: {
                    Text("填写自建 NeteaseCloudMusicApi Enhanced 地址，例如 http://192.168.1.244:3000。手机需与服务器在同一网络，或已配置 Tailscale。")
                }
            }
            .navigationTitle("服务器设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        apiBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                }
            }
        }
    }
}
