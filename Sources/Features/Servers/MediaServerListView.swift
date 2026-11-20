import SwiftUI

/// 媒体服务器列表（Subsonic / Navidrome / Jellyfin / Emby）
struct MediaServerListView: View {
    @ObservedObject private var store = MediaServerStore.shared

    @State private var showEditor = false
    @State private var editingServer: MediaServer?

    var body: some View {
        List {
            Section {
                ForEach(store.servers) { server in
                    NavigationLink {
                        MediaServerLibraryView(server: server)
                    } label: {
                        row(for: server)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("删除", role: .destructive) {
                            store.remove(server)
                        }
                        Button("编辑") {
                            editingServer = server
                            showEditor = true
                        }
                        .tint(.orange)
                    }
                }
            } footer: {
                if store.servers.isEmpty {
                    Text("尚未添加媒体服务器。支持 Subsonic / Navidrome、Jellyfin 与 Emby，可添加多台服务器。")
                } else {
                    Text("点击服务器浏览专辑并播放；左滑可编辑或删除。密钥保存在系统钥匙串中。")
                }
            }
        }
        .adaptiveListBackground()
        .navigationTitle("媒体服务器")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingServer = nil
                    showEditor = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor, onDismiss: { editingServer = nil }) {
            MediaServerEditView(server: editingServer)
        }
    }

    private func row(for server: MediaServer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: server.kind.icon)
                .font(.title3)
                .foregroundStyle(Color.splayerAccent)
                .frame(width: 36, height: 36)
                .background(Color.splayerAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(server.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(server.kind.shortTitle) · \(server.username)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(server.baseURL)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 添加 / 编辑媒体服务器
struct MediaServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MediaServerStore.shared

    let server: MediaServer?

    @State private var kind: MediaServerKind
    @State private var name: String
    @State private var address: String
    @State private var username: String
    @State private var password: String

    @State private var isTesting = false
    @State private var alertInfo: AlertInfo?

    private struct AlertInfo: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    init(server: MediaServer?) {
        self.server = server
        _kind = State(initialValue: server?.kind ?? .subsonic)
        _name = State(initialValue: server?.name ?? "")
        _address = State(initialValue: server?.baseURL ?? "")
        _username = State(initialValue: server?.username ?? "")
        _password = State(initialValue: server.map { Keychain.read($0.secretKey) ?? "" } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("类型") {
                    Picker("服务器类型", selection: $kind) {
                        ForEach(MediaServerKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }

                Section {
                    TextField("名称（可选）", text: $name)
                    TextField("服务器地址", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                } header: {
                    Text("连接")
                } footer: {
                    Text(hint)
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Label(isTesting ? "正在连接…" : "测试连接", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting || address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle(server == nil ? "添加服务器" : "编辑服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .alert(item: $alertInfo) { info in
                Alert(
                    title: Text(info.title),
                    message: Text(info.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var hint: String {
        switch kind {
        case .subsonic:
            return "支持 Subsonic 协议（Navidrome、Airsonic、Gonic 等），地址例如 http://192.168.1.10:4533。"
        case .jellyfin:
            return "地址例如 http://192.168.1.10:8096。首次浏览时会自动登录并保存访问令牌。"
        case .emby:
            return "地址例如 http://192.168.1.10:8096。Emby 与 Jellyfin API 兼容。"
        }
    }

    private var canSave: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
    }

    private func normalizedAddress() -> String? {
        let probe = MediaServer(
            id: server?.id ?? UUID(),
            kind: kind,
            name: name,
            baseURL: address,
            username: username,
            token: server?.token,
            userID: server?.userID
        )
        return probe.normalizedBaseURL?.absoluteString
    }

    private func testConnection() {
        guard let normalized = normalizedAddress() else {
            alertInfo = AlertInfo(title: "地址无效", message: "请填写正确的服务器地址。")
            return
        }
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            alertInfo = AlertInfo(title: "信息不完整", message: "请填写用户名与密码。")
            return
        }

        let probe = MediaServer(
            id: server?.id ?? UUID(),
            kind: kind,
            name: name,
            baseURL: normalized,
            username: username,
            token: nil,
            userID: nil
        )

        isTesting = true
        Task {
            do {
                try await MediaServerClient.test(server: probe, secret: password)
                isTesting = false
                alertInfo = AlertInfo(title: "连接成功", message: "已成功连接到服务器。")
            } catch {
                isTesting = false
                alertInfo = AlertInfo(title: "连接失败", message: error.localizedDescription)
            }
        }
    }

    private func save() {
        guard let normalized = normalizedAddress() else {
            alertInfo = AlertInfo(title: "地址无效", message: "请填写正确的服务器地址。")
            return
        }
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            alertInfo = AlertInfo(title: "信息不完整", message: "请填写用户名与密码。")
            return
        }

        var target = server ?? MediaServer(
            id: UUID(),
            kind: kind,
            name: name,
            baseURL: normalized,
            username: username,
            token: nil,
            userID: nil
        )
        target.kind = kind
        target.name = name
        target.baseURL = normalized
        target.username = username

        store.save(target, secret: password)
        dismiss()
    }
}
