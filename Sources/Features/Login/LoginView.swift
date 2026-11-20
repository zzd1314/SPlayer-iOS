import SwiftUI
import UIKit

/// 扫码登录：/login/qr/key → /login/qr/create → 轮询 /login/qr/check
struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var qrImage: UIImage?
    @State private var statusText = ""
    @State private var errorText: String?
    @State private var isLoading = true
    @State private var pollTask: Task<Void, Never>?
    @State private var showServerSettings = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 6) {
                Text("SPlayer")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.splayerAccent)
                Text("使用网易云音乐 App 扫码登录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .frame(width: 248, height: 248)
                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 208, height: 208)
                } else if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 64))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("重试") {
                    Task { await start() }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            HStack(spacing: 24) {
                Button {
                    Task { await start() }
                } label: {
                    Label("刷新二维码", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)

                Button {
                    showServerSettings = true
                } label: {
                    Label("服务器设置", systemImage: "server.rack")
                }
            }
            .font(.footnote)
        }
        .padding()
        .sheet(isPresented: $showServerSettings) {
            ServerSettingsView()
        }
        .onChange(of: showServerSettings) { _, isShowing in
            if !isShowing {
                Task { await start() }
            }
        }
        .task {
            if qrImage == nil {
                await start()
            }
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private func start() async {
        pollTask?.cancel()
        isLoading = true
        errorText = nil
        qrImage = nil
        statusText = "正在获取二维码…"

        do {
            let api = NeteaseAPI()
            let key = try await api.qrKey()
            let created = try await api.qrCreate(key: key)
            if let raw = created.image,
               let data = NeteaseAPI.imageData(fromDataURL: raw),
               let image = UIImage(data: data) {
                qrImage = image
            }
            statusText = "等待扫码"
            isLoading = false
            poll(key: key)
        } catch {
            isLoading = false
            errorText = error.localizedDescription
            statusText = ""
        }
    }

    private func poll(key: String) {
        pollTask = Task {
            let api = NeteaseAPI()
            while !Task.isCancelled {
                do {
                    let result = try await api.qrCheck(key: key)
                    switch result.code {
                    case 800:
                        statusText = "二维码已过期，请刷新"
                        return
                    case 801:
                        statusText = "等待扫码"
                    case 802:
                        statusText = "已扫码，请在手机上确认"
                    case 803:
                        statusText = "登录成功"
                        if let cookie = result.cookie, !cookie.isEmpty {
                            await auth.signIn(cookie: cookie)
                        } else {
                            errorText = "登录返回的 Cookie 为空，请重试"
                        }
                        return
                    default:
                        if let message = result.message, !message.isEmpty {
                            statusText = message
                        }
                    }
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch is CancellationError {
                    return
                } catch {
                    errorText = error.localizedDescription
                    return
                }
            }
        }
    }
}
