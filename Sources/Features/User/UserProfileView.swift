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

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

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
                        statText("关注", profile.follows)
                        statText("粉丝", profile.followeds)
                        statText("歌单", profile.playlistCount)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
    }
}
