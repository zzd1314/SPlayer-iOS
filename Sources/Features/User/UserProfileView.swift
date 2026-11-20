import SwiftUI

/// 用户主页：头像 / 昵称 / 签名 / 关注与粉丝 + 公开歌单
struct UserProfileView: View {
    let userId: Int
    let nickname: String?

    @EnvironmentObject private var auth: AuthStore

    @State private var profile: UserProfile?
    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?
    @State private var isFollowed = false
    @State private var isFollowBusy = false
    @State private var actionError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                listenRankLink

                if !playlists.isEmpty {
                    Text("歌单")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 2)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(playlists) { playlist in
                            NavigationLink {
                                PlaylistDetailView(playlist: playlist)
                            } label: {
                                PlaylistCard(playlist: playlist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if loadedOnce, !isLoading, errorText == nil {
                    Text("暂无公开歌单")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle(profile?.nickname ?? nickname ?? "用户主页")
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
            if isLoading, profile == nil, playlists.isEmpty {
                ProgressView()
            }
        }
        .overlay {
            if let errorText, profile == nil, playlists.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
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

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CoverImage(urlString: profile?.avatarUrl, size: 72, cornerRadius: 36)

            VStack(alignment: .leading, spacing: 5) {
                Text(profile?.nickname ?? nickname ?? "用户 \(userId)")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                if let signature = profile?.signature, !signature.isEmpty {
                    Text(signature)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let profile {
                    HStack(spacing: 14) {
                        NavigationLink {
                            UserRelationView(userId: profile.userId, kind: .following)
                        } label: {
                            statText("关注", profile.follows)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            UserRelationView(userId: profile.userId, kind: .followers)
                        } label: {
                            statText("粉丝", profile.followeds)
                        }
                        .buttonStyle(.plain)

                        statText("歌单", profile.playlistCount)
                    }
                    .padding(.top, 2)
                }

                if canFollow {
                    Button {
                        Task { await toggleFollow() }
                    } label: {
                        Text(isFollowed ? "已关注" : "关注")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                isFollowed ? Color.secondary.opacity(0.18) : Color.splayerAccent,
                                in: Capsule()
                            )
                            .foregroundStyle(isFollowed ? Color.primary : Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(isFollowBusy)
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var canFollow: Bool {
        guard auth.isLoggedIn, let myId = auth.profile?.userId else { return false }
        return myId != userId
    }

    private var listenRankLink: some View {
        NavigationLink {
            ListenRankView(userId: userId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.splayerAccent)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.splayerAccent.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )

                Text("听歌排行")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statText(_ title: String, _ count: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(count ?? 0)")
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            profile = try await api.userDetail(uid: userId, cookie: auth.cookie)
        } catch {
            errorText = error.localizedDescription
        }
        playlists = (try? await api.userPlaylists(uid: userId, cookie: auth.cookie)) ?? []

        // 通过我的关注列表判断是否已关注该用户
        if let myId = auth.profile?.userId, myId != userId,
           let follows = try? await api.userFollows(uid: myId, cookie: auth.cookie) {
            isFollowed = follows.contains { $0.userId == userId }
        }
    }

    private func toggleFollow() async {
        guard !isFollowBusy, let cookie = auth.cookie else { return }
        isFollowBusy = true
        defer { isFollowBusy = false }

        let target = !isFollowed
        isFollowed = target
        do {
            try await NeteaseAPI().setUserFollowed(id: userId, follow: target, cookie: cookie)
        } catch {
            isFollowed = !target
            actionError = error.localizedDescription
        }
    }
}
