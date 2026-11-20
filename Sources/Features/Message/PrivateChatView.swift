import SwiftUI

/// 私信会话
struct PrivateChatView: View {
    let contact: RecentContact

    @EnvironmentObject private var auth: AuthStore

    @State private var messages: [PrivateMessage] = []
    @State private var text = ""
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var isSending = false
    @State private var loadedOnce = false
    @State private var hasMore = false
    @State private var errorText: String?

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if hasMore {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Text("加载更早的消息")
                                    .font(.caption)
                            }
                        }
                        .disabled(isLoadingMore)
                    }

                    ForEach(messages) { message in
                        bubble(for: message)
                            .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of: messages.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .navigationTitle(contact.nickname)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            composer
        }
        .task {
            if !loadedOnce {
                await load()
            }
        }
        .overlay {
            if isLoading, messages.isEmpty {
                ProgressView()
            } else if loadedOnce, messages.isEmpty, errorText == nil, !isLoading {
                ContentUnavailableView(
                    "暂无消息",
                    systemImage: "bubble.left",
                    description: Text("发一条消息开始聊天吧")
                )
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("发送消息…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )

            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(canSend ? Color.splayerAccent : Color.secondary)
                        .frame(width: 32, height: 32)
                }
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func bubble(for message: PrivateMessage) -> some View {
        let mine = message.fromUserId == auth.profile?.userId
        return HStack(alignment: .bottom, spacing: 8) {
            if mine {
                Spacer(minLength: 48)
            }

            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                Text(message.content ?? "")
                    .font(.subheadline)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        mine ? Color.splayerAccent : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                if let date = message.date {
                    Text(timeText(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !mine {
                Spacer(minLength: 48)
            }
        }
    }

    private func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "M/d HH:mm"
        }
        return formatter.string(from: date)
    }

    private func load() async {
        guard !isLoading else { return }
        guard let cookie = auth.cookie else {
            errorText = "请先登录后查看私信"
            return
        }
        guard let uid = contact.contactUserId else {
            errorText = "无法获取对方用户信息"
            return
        }

        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            let result = try await NeteaseAPI().privateMessages(
                uid: uid,
                limit: 30,
                offset: 0,
                cookie: cookie
            )
            messages = Array(result.messages.reversed())
            hasMore = result.more
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore else { return }
        guard let cookie = auth.cookie, let uid = contact.contactUserId else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await NeteaseAPI().privateMessages(
                uid: uid,
                limit: 30,
                offset: messages.count,
                cookie: cookie
            )
            let older = Array(result.messages.reversed())
            messages.insert(contentsOf: older, at: 0)
            hasMore = result.more
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func send() async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        guard let cookie = auth.cookie, let uid = contact.contactUserId else {
            errorText = "请先登录后发送私信"
            return
        }

        isSending = true
        defer { isSending = false }

        do {
            try await NeteaseAPI().sendPrivateMessage(uid: uid, text: content, cookie: cookie)
            text = ""
            messages.append(
                PrivateMessage(
                    remoteId: nil,
                    fromUserId: auth.profile?.userId,
                    toUserId: uid,
                    content: content,
                    time: Int(Date().timeIntervalSince1970 * 1000)
                )
            )
        } catch {
            errorText = error.localizedDescription
        }
    }
}
