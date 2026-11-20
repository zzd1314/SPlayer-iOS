import SwiftUI

/// 设置：账号 / 服务器地址 / 关于
struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @AppStorage("apiBaseURL") private var apiBaseURL: String = AppSettings.defaultBaseURL
    @AppStorage("audioLevel") private var audioLevel = "exhigh"

    @State private var cacheSize: Int64 = 0

    private var cacheText: String {
        cacheSize == 0 ? "0 MB" : ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("账号") {
                    if let profile = auth.profile {
                        LabeledContent("昵称", value: profile.nickname)
                        LabeledContent("UID", value: String(profile.userId))
                    } else if auth.isLoggedIn {
                        LabeledContent("状态", value: auth.isLoadingProfile ? "正在获取资料…" : "已登录")
                    } else {
                        LabeledContent("状态", value: "未登录")
                    }

                    if auth.isLoggedIn {
                        Button("退出登录", role: .destructive) {
                            auth.signOut()
                        }
                    }
                }

                Section("服务器") {
                    TextField("API 地址", text: $apiBaseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .onSubmit {
                            apiBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    if let error = auth.profileError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("播放") {
                    Picker("音质", selection: $audioLevel) {
                        Text("标准").tag("standard")
                        Text("较高").tag("higher")
                        Text("极高").tag("exhigh")
                    }
                }

                Section("存储") {
                    LabeledContent("音频缓存", value: cacheText)
                    Button("清除缓存", role: .destructive) {
                        AudioCache.clear()
                        cacheSize = AudioCache.totalSize()
                    }
                    .disabled(cacheSize == 0)
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("阶段", value: "M5 歌词与设置")
                }
            }
            .navigationTitle("设置")
            .onAppear {
                cacheSize = AudioCache.totalSize()
            }
        }
    }
}
