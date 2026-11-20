import SwiftUI

/// 消息中心：最近联系人列表
struct MessageCenterView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var contacts: [RecentContact] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        List {
            ForEach(contacts) { contact in
                NavigationLink {
                    PrivateChatView(contact: contact)
                } label: {
                    row(for: contact)
                }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
        }
        .task {
            if !loadedOnce {
                await load()
            }
        }
        .overlay {
            if isLoading, contacts.isEmpty {
                ProgressView()
            } else if let errorText, contacts.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
            } else if loadedOnce, contacts.isEmpty, !isLoading {
                ContentUnavailableView(
                    "暂无消息",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("与好友的私信会显示在这里")
                )
            }
        }
    }

    private func row(for contact: RecentContact) -> some View {
        HStack(spacing: 12) {
            avatar(for: contact)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(contact.nickname)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let time = contact.lastMsgTime {
                        Text(timeText(time))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Text(contact.lastMsg ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let count = contact.newMsgCount, count > 0 {
                        Text("\(count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func avatar(for contact: RecentContact) -> some View {
        if let urlString = contact.avatarURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholderAvatar
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(Circle())
        } else {
            placeholderAvatar
                .frame(width: 46, height: 46)
        }
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemFill))
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
        }
    }

    private func timeText(_ milliseconds: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            return "昨天"
        } else {
            formatter.dateFormat = "M/d"
        }
        return formatter.string(from: date)
    }

    private func load() async {
        guard !isLoading else { return }
        guard let cookie = auth.cookie else {
            errorText = "请先登录后查看消息"
            return
        }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            contacts = try await NeteaseAPI().recentContacts(cookie: cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
