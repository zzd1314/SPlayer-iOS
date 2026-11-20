import SwiftUI

/// 用户关系类型
enum UserRelationKind {
    case following
    case followers

    var title: String {
        switch self {
        case .following: return "关注"
        case .followers: return "粉丝"
        }
    }

    var emptyText: String {
        switch self {
        case .following: return "还没有关注任何人"
        case .followers: return "还没有粉丝"
        }
    }
}

/// 关注 / 粉丝列表
struct UserRelationView: View {
    let userId: Int
    let kind: UserRelationKind

    @EnvironmentObject private var auth: AuthStore

    @State private var users: [UserSummary] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        List {
            ForEach(users) { user in
                NavigationLink {
                    UserProfileView(userId: user.userId, nickname: user.nickname)
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(urlString: user.avatarUrl, size: 44, cornerRadius: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.nickname)
                                .font(.body)
                                .lineLimit(1)
                            if let signature = user.signature, !signature.isEmpty {
                                Text(signature)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle(kind.title)
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
            if isLoading, users.isEmpty {
                ProgressView()
            } else if let errorText, users.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
            } else if loadedOnce, users.isEmpty, !isLoading {
                ContentUnavailableView(
                    kind.emptyText,
                    systemImage: "person.2",
                    description: Text("稍后再来看看吧")
                )
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        let api = NeteaseAPI()
        do {
            switch kind {
            case .following:
                users = try await api.userFollows(uid: userId, cookie: auth.cookie)
            case .followers:
                users = try await api.userFolloweds(uid: userId, cookie: auth.cookie)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}
