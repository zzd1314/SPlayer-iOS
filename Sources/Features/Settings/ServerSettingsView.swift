import SwiftUI

/// 服务器地址设置（登录页 / 设置页共用）
struct ServerSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("apiBaseURL") private var apiBaseURL: String = AppSettings.defaultBaseURL
    @AppStorage("useBuiltinAPI") private var useBuiltinAPI = true

    @State private var builtinRunning = false
    @State private var builtinDetail = "未启动"

    var body: some View {
        Form {
            Section {
                Toggle("使用内置 API 服务", isOn: $useBuiltinAPI)
            } header: {
                Text("API 服务")
            } footer: {
                Text("内置 Rust 版网易云 API，无需自建服务器，App 直接连接网易云。关闭后可改用局域网内的 NeteaseCloudMusicApi Enhanced。")
            }

            Section {
                if useBuiltinAPI {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(builtinRunning ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(builtinDetail)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TextField(AppSettings.defaultBaseURL, text: $apiBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            } footer: {
                if useBuiltinAPI {
                    Text("服务仅监听本机 127.0.0.1，不对外网开放。")
                } else {
                    Text("填写自建 NeteaseCloudMusicApi Enhanced 地址，例如 http://192.168.1.244:3000。手机需与服务器在同一网络，或已配置 Tailscale。")
                }
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
        .onAppear(perform: refreshStatus)
        .onChange(of: useBuiltinAPI) { _, _ in
            refreshStatus()
        }
    }

    /// 刷新内置服务状态（开启时顺带触发启动）
    private func refreshStatus() {
        guard useBuiltinAPI else { return }
        let service = BuiltinAPIService.shared
        builtinRunning = service.start()
        if builtinRunning, let url = service.baseURL {
            builtinDetail = "运行中 · \(url)"
        } else {
            builtinDetail = service.lastError ?? "内置服务未启动"
        }
    }
}
