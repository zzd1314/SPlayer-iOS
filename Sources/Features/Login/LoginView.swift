import SwiftUI
import UIKit
import CoreImage

/// 登录：扫码 / 手机号验证码 / 邮箱验证码
struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase

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

    /// 手机号登录方式
    private enum PhoneAuthMode: String, CaseIterable, Identifiable {
        case captcha
        case password

        var id: String { rawValue }

        var title: String {
            switch self {
            case .captcha: return "验证码"
            case .password: return "密码"
            }
        }
    }

    // 扫码
    @State private var qrImage: UIImage?
    @State private var statusText = ""
    @State private var isLoadingQR = true
    @State private var qrError: String?
    @State private var pollTask: Task<Void, Never>?
    /// 二维码请求代次，用于丢弃过期的异步结果
    @State private var qrGeneration = 0
    /// 轮询是否仍在运行
    @State private var isPolling = false

    // 验证码
    @State private var phone = ""
    @State private var email = ""
    @State private var captcha = ""
    @State private var password = ""
    @State private var phoneAuthMode: PhoneAuthMode = .captcha
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
            if !isShowing, mode == .qr, !isPolling {
                Task { await startQR() }
            }
        }
        .onChange(of: mode) { _, newMode in
            formError = nil
            formMessage = nil
            if newMode == .qr {
                Task { await startQR() }
            } else {
                pollTask?.cancel()
                pollTask = nil
                isPolling = false
            }
        }
        .onChange(of: phoneAuthMode) { _, _ in
            formError = nil
            formMessage = nil
        }
        .onChange(of: scenePhase) { _, phase in
            // 回到前台后若轮询已停止，重新获取二维码，避免出现“有码但扫不动”
            guard phase == .active, mode == .qr else { return }
            if !isPolling && !isLoadingQR {
                Task { await startQR() }
            }
        }
        .task {
            if !isPolling {
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

            Picker("手机号登录方式", selection: $phoneAuthMode) {
                ForEach(PhoneAuthMode.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if phoneAuthMode == .captcha {
                captchaRow
            } else {
                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(fieldBackground)
            }

            if let formMessage {
                Text(formMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let errorText = formError {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if errorText.contains("风险") || errorText.contains("安全") {
                    HStack(spacing: 14) {
                        if phoneAuthMode == .captcha {
                            Button("改用密码登录") {
                                phoneAuthMode = .password
                                formError = nil
                            }
                        }
                        Button("改用扫码登录") {
                            mode = .qr
                            formError = nil
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.splayerAccent)
                }
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
        case .phone: return isPhoneValid && phoneAuthMode == .captcha
        case .email: return isEmailValid
        case .qr: return false
        }
    }

    private var canSubmit: Bool {
        switch mode {
        case .phone:
            guard isPhoneValid else { return false }
            return phoneAuthMode == .captcha ? captcha.count >= 4 : password.count >= 6
        case .email:
            return isEmailValid && captcha.count >= 4
        case .qr:
            return false
        }
    }

    // MARK: - 操作

    private func startQR() async {
        qrGeneration += 1
        let generation = qrGeneration

        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        isLoadingQR = true
        qrError = nil
        qrImage = nil
        statusText = "正在获取二维码…"

        do {
            let api = NeteaseAPI()
            let key = try await api.qrKey()
            let created = try await api.qrCreate(key: key)
            // 期间用户可能已刷新或切换登录方式，丢弃过期的结果
            guard generation == qrGeneration else { return }

            if let raw = created.image,
               let data = NeteaseAPI.imageData(fromDataURL: raw),
               let image = UIImage(data: data) {
                qrImage = image
            } else {
                // 接口未返回图片时用 qrurl 在本地生成
                qrImage = Self.makeQRImage(from: created.url)
            }

            guard qrImage != nil else {
                isLoadingQR = false
                statusText = "二维码加载失败"
                qrError = "请点击刷新二维码重试"
                return
            }

            statusText = "使用网易云音乐 App 扫码"
            isLoadingQR = false
            poll(key: key, generation: generation)
        } catch {
            guard generation == qrGeneration else { return }
            isLoadingQR = false
            statusText = "二维码加载失败"
            qrError = error.localizedDescription
        }
    }

    private func poll(key: String, generation: Int) {
        isPolling = true
        pollTask = Task { @MainActor in
            let api = NeteaseAPI()
            var interval: UInt64 = 2_000_000_000
            var failureCount = 0

            defer {
                if generation == qrGeneration {
                    isPolling = false
                }
            }

            while !Task.isCancelled {
                guard generation == qrGeneration else { return }
                do {
                    let result = try await api.qrCheck(key: key)
                    guard generation == qrGeneration else { return }
                    failureCount = 0
                    qrError = nil

                    switch result.code {
                    case 800:
                        // 二维码已过期：自动换新，不需要用户手动点刷新
                        statusText = "二维码已过期，正在刷新…"
                        Task { await startQR() }
                        return
                    case 801:
                        statusText = "等待扫码"
                        interval = 2_000_000_000
                    case 802:
                        statusText = "已扫码，请在手机上确认"
                        interval = 1_000_000_000
                    case 803:
                        statusText = "登录成功"
                        if let cookie = result.cookie, !cookie.isEmpty {
                            await auth.signIn(cookie: cookie)
                        } else {
                            qrError = "登录信息无效，正在刷新二维码…"
                            Task { await startQR() }
                        }
                        return
                    default:
                        if let message = result.message, !message.isEmpty {
                            statusText = message
                        }
                    }
                    try await Task.sleep(nanoseconds: interval)
                } catch is CancellationError {
                    return
                } catch {
                    // 网络异常时不放弃：保留当前二维码，退避后继续轮询
                    guard generation == qrGeneration else { return }
                    failureCount += 1
                    statusText = "网络异常，正在重试…"
                    let backoff = min(UInt64(failureCount), 5) * 1_000_000_000
                    try? await Task.sleep(nanoseconds: backoff)
                }
            }
        }
    }

    /// 用 CoreImage 在本地生成二维码图片
    private static func makeQRImage(from string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
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
                if phoneAuthMode == .captcha {
                    try await auth.login(
                        phone: trimmedPhone,
                        captcha: captcha.trimmingCharacters(in: .whitespacesAndNewlines),
                        countryCode: countryCode
                    )
                } else {
                    try await auth.login(
                        phone: trimmedPhone,
                        password: password,
                        countryCode: countryCode
                    )
                }
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
