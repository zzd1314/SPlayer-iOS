import SwiftUI

/// 歌曲评论：热门评论 + 最新评论（只读）
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

    var body: some View {
        NavigationStack {
            List {
                if !hotComments.isEmpty {
                    Section("热门评论") {
                        ForEach(hotComments) { comment in
                            CommentRow(comment: comment)
                        }
                    }
                }

                if !comments.isEmpty {
                    Section("最新评论") {
                        ForEach(comments) { comment in
                            CommentRow(comment: comment)
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
        }
    }

    private var navigationTitle: String {
        total > 0 ? "评论 \(total)" : "评论"
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
}

private struct CommentRow: View {
    let comment: CommentItem

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
                    if let likes = comment.likedCount, likes > 0 {
                        Label("\(likes)", systemImage: "heart")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
