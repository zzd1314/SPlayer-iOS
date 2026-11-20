import SwiftUI
import UIKit

/// 登录：扫码 / 手机号验证码 / 邮箱验证码
struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    private enum LoginMode: String, CaseIterable, Identifiable {
        case qr
        case phone
        case email

        var id: String { rawValue }

        var title: String {
            switch self {
            case .qr: return "扫码登录"
            case .phone: return "手机号"
            case .email: return "邮箱"
            }
        }
    }

    @State private var mode: LoginMode = .qr

    // 扫码
    @State private var qrImage: UIImage?
    @State private var statusText = ""
    @State private var isLoadingQR = true
    @State private var qrError: String?
    @State private var pollTask: Task<Void, Never>?

    // 验证码
    @State private var phone = ""
    @State private var email = ""
    @State private var captcha = ""
    @State private var countryCode = "86"
    @State private var countdown = 0
    @State private var isSendingCode = false
    @State private var isLoggingIn = false
    @State private var formMessage: String?
    @State private var formError: String?
    @State private var countdownTask: Task<Void, Never>?

    @State private var showServerSettings = false

    private let countryCodes = ["86", "852", "853", "886", "1", "81", "82", "65"]

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                Picker("登录方式", selection: $mode) {
                    ForEach(LoginMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch mode {
                    case .qr:
                        qrSection
                    case .phone:
                        phoneSection
                    case .email:
                        emailSection
                    }
                }
                .padding(.top, 4)

                serverButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            LinearGradient(
                colors: [Color.splayerAccent.opacity(0.16), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showServerSettings) {
            NavigationStack {
                ServerSettingsView()
            }
        }
        .onChange(of: showServerSettings) { _, isShowing in
            if !isShowing, mode == .qr {
                Task { await startQR() }
            }
        }
        .onChange(of: mode) { _, newMode in
            formError = nil
            formMessage = nil
            if newMode == .qr {
                if qrImage == nil {
                    Task { await startQR() }
                }
            } else {
                pollTask?.cancel()
            }
        }
        .task {
            if qrImage == nil {
                await startQR()
            }
        }
        .onDisappear {
            pollTask?.cancel()
            countdownTask?.cancel()
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.splayerAccent, Color(hex: 0xFFB26B)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                    .shadow(color: Color.splayerAccent.opacity(0.35), radius: 16, y: 8)
                Image(systemName: "music.note")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("SPlayer")
                .font(.largeTitle.weight(.bold))
            Text("登录网易云音乐，同步你的歌单")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 扫码

    private var qrSection: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
                    .frame(width: 236, height: 236)

                if let qrImage {
                    Image(uiImage: qrImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 200, height: 200)
                } else if isLoadingQR {
                    ProgressView()
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 60))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let qrError {
                Text(qrError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await startQR() }
            } label: {
                Label("刷新二维码", systemImage: "arrow.clockwise")
                    .font(.footnote)
            }
            .disabled(isLoadingQR)
        }
    }

    // MARK: - 手机号

    private var phoneSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(countryCodes, id: \.self) { code in
                        Button("+\(code)") { countryCode = code }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("+\(countryCode)")
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12)
                    .frame(height: 50)
                    .background(fieldBackground)
                }

                TextField("手机号", text: $phone)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(fieldBackground)
            }

            captchaRow

            if let formMessage {
                Text(formMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let formError {
                Text(formError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            loginButton
        }
    }

    // MARK: - 邮箱

    private var emailSection: some View {
        VStack(spacing: 12) {
            TextField("邮箱地址", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(fieldBackground)

            captchaRow

            if let formMessage {
                Text(formMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let formError {
                Text(formError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            loginButton
        }
    }

    private var captchaRow: some View {
        HStack(spacing: 10) {
            TextField("验证码", text: $captcha)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(fieldBackground)

            Button {
                Task { await sendCode() }
            } label: {
                Group {
                    if isSendingCode {
                        ProgressView()
                    } else {
                        Text(countdown > 0 ? "\(countdown)s" : "获取验证码")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .frame(width: 92, height: 50)
                .background(
                    Color.splayerAccent.opacity(canSendCode ? 0.14 : 0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .foregroundStyle(canSendCode ? Color.splayerAccent : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canSendCode)
        }
    }

    private var loginButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isLoggingIn {
                    ProgressView()
                        .tint(.white)
                }
                Text(isLoggingIn ? "登录中…" : "登录")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                Color.splayerAccent.opacity(canSubmit ? 1 : 0.45),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isLoggingIn)
    }

    private var serverButton: some View {
        Button {
            showServerSettings = true
        } label: {
            Label("服务器设置", systemImage: "server.rack")
                .font(.footnote)
        }
        .padding(.top, 4)
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemBackground))
    }

    // MARK: - 校验

    private var trimmedPhone: String {
        phone.filter(\.isNumber)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPhoneValid: Bool {
        (7...15).contains(trimmedPhone.count)
    }

    private var isEmailValid: Bool {
        guard let at = trimmedEmail.firstIndex(of: "@") else { return false }
        let domain = trimmedEmail[trimmedEmail.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    private var canSendCode: Bool {
        guard countdown == 0, !isSendingCode else { return false }
        switch mode {
        case .phone: return isPhoneValid
        case .email: return isEmailValid
        case .qr: return false
        }
    }

    private var canSubmit: Bool {
        guard captcha.count >= 4 else { return false }
        switch mode {
        case .phone: return isPhoneValid
        case .email: return isEmailValid
        case .qr: return false
        }
    }

    // MARK: - 操作

    private func startQR() async {
        pollTask?.cancel()
        isLoadingQR = true
        qrError = nil
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
            statusText = "使用网易云音乐 App 扫码"
            isLoadingQR = false
            poll(key: key)
        } catch {
            isLoadingQR = false
            qrError = error.localizedDescription
            statusText = ""
        }
    }

    private func poll(key: String) {
        pollTask = Task { @MainActor in
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
                            qrError = "登录返回的 Cookie 为空，请重试"
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
                    qrError = error.localizedDescription
                    return
                }
            }
        }
    }

    private func sendCode() async {
        guard canSendCode else { return }
        isSendingCode = true
        formError = nil
        formMessage = nil
        defer { isSendingCode = false }

        do {
            switch mode {
            case .phone:
                try await auth.sendLoginCaptcha(phone: trimmedPhone, countryCode: countryCode)
            case .email:
                try await auth.sendLoginCaptcha(email: trimmedEmail)
            case .qr:
                return
            }
            formMessage = "验证码已发送，请查收"
            startCountdown()
        } catch {
            formError = error.localizedDescription
        }
    }

    private func submit() async {
        guard canSubmit, !isLoggingIn else { return }
        isLoggingIn = true
        formError = nil
        formMessage = nil
        defer { isLoggingIn = false }

        do {
            switch mode {
            case .phone:
                try await auth.login(
                    phone: trimmedPhone,
                    captcha: captcha.trimmingCharacters(in: .whitespacesAndNewlines),
                    countryCode: countryCode
                )
            case .email:
                try await auth.login(
                    email: trimmedEmail,
                    captcha: captcha.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            case .qr:
                return
            }
        } catch {
            formError = error.localizedDescription
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdown = 60
        countdownTask = Task { @MainActor in
            while countdown > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
            }
        }
    }
}
