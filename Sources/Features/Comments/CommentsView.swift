import SwiftUI

/// 歌曲评论：热门 + 最新，支持点赞与发表评论
struct CommentsView: View {
    let songId: Int
    let songName: String

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var hotComments: [CommentItem] = []
    @State private var comments: [CommentItem] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?
    @State private var draft = ""
    @State private var isSending = false
    @State private var actionError: String?

    var body: some View {
        NavigationStack {
            List {
                if !hotComments.isEmpty {
                    Section("热门评论") {
                        ForEach(hotComments) { comment in
                            CommentRow(
                                comment: comment,
                                canLike: auth.isLoggedIn,
                                onToggleLike: {
                                    Task { await toggleLike(comment) }
                                }
                            )
                        }
                    }
                }

                if !comments.isEmpty {
                    Section("最新评论") {
                        ForEach(comments) { comment in
                            CommentRow(
                                comment: comment,
                                canLike: auth.isLoggedIn,
                                onToggleLike: {
                                    Task { await toggleLike(comment) }
                                }
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if auth.isLoggedIn {
                    composer
                }
            }
            .task {
                if !loadedOnce {
                    await load()
                }
            }
            .overlay {
                if isLoading, hotComments.isEmpty, comments.isEmpty {
                    ProgressView()
                } else if let errorText, hotComments.isEmpty, comments.isEmpty, !isLoading {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorText)
                    } actions: {
                        Button("重试") {
                            Task { await load() }
                        }
                    }
                } else if loadedOnce, hotComments.isEmpty, comments.isEmpty, !isLoading {
                    ContentUnavailableView("暂无评论", systemImage: "bubble.left", description: Text(songName))
                }
            }
            .alert("操作失败", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
        }
    }

    private var navigationTitle: String {
        total > 0 ? "评论 \(total)" : "评论"
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("说点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(canSend ? Color.splayerAccent : Color.secondary)
                }
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            let result = try await NeteaseAPI().songComments(id: songId, cookie: auth.cookie)
            hotComments = result.hot
            comments = result.latest
            total = result.total
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func send() async {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending, let cookie = auth.cookie else { return }
        isSending = true
        defer { isSending = false }

        do {
            try await NeteaseAPI().sendComment(songId: songId, content: content, cookie: cookie)
            draft = ""
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleLike(_ comment: CommentItem) async {
        guard let cookie = auth.cookie else { return }
        let target = !(comment.liked ?? false)
        updateLikeState(commentId: comment.id, liked: target, delta: target ? 1 : -1)

        do {
            try await NeteaseAPI().setCommentLiked(
                songId: songId,
                commentId: comment.id,
                like: target,
                cookie: cookie
            )
        } catch {
            updateLikeState(commentId: comment.id, liked: !target, delta: target ? -1 : 1)
        }
    }

    private func updateLikeState(commentId: Int, liked: Bool, delta: Int) {
        if let index = hotComments.firstIndex(where: { $0.id == commentId }) {
            hotComments[index].liked = liked
            hotComments[index].likedCount = max(0, (hotComments[index].likedCount ?? 0) + delta)
        }
        if let index = comments.firstIndex(where: { $0.id == commentId }) {
            comments[index].liked = liked
            comments[index].likedCount = max(0, (comments[index].likedCount ?? 0) + delta)
        }
    }
}

private struct CommentRow: View {
    let comment: CommentItem
    let canLike: Bool
    let onToggleLike: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CoverImage(urlString: comment.user?.avatarUrl, size: 34, cornerRadius: 17)

            VStack(alignment: .leading, spacing: 4) {
                Text(comment.user?.nickname ?? "匿名用户")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(comment.content)
                    .font(.subheadline)

                HStack(spacing: 10) {
                    if let date = comment.dateText {
                        Text(date)
                    }

                    Button(action: onToggleLike) {
                        Label(
                            "\(comment.likedCount ?? 0)",
                            systemImage: (comment.liked ?? false) ? "heart.fill" : "heart"
                        )
                        .foregroundStyle((comment.liked ?? false) ? Color.splayerAccent : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canLike)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
