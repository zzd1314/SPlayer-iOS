import SwiftUI

/// 资料库：账号信息 + 歌单卡片网格（贴近桌面版）
struct LibraryView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16, alignment: .top)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileHeader

                    if !playlists.isEmpty {
                        Text("我的歌单")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 2)

                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(playlists) { playlist in
                                NavigationLink(value: playlist) {
                                    PlaylistCard(playlist: playlist)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("资料库")
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .refreshable {
                await load()
            }
            .task {
                if playlists.isEmpty {
                    await load()
                }
            }
            .overlay {
                if isLoading && playlists.isEmpty {
                    ProgressView()
                }
            }
            .overlay {
                if let errorText, playlists.isEmpty, !isLoading {
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
    }

    private var profileHeader: some View {
        HStack(spacing: 14) {
            CoverImage(urlString: auth.profile?.avatarUrl, size: 56, cornerRadius: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(auth.profile?.nickname ?? "网易云音乐")
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text(playlists.isEmpty ? "正在同步歌单…" : "\(playlists.count) 个歌单")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        if auth.profile == nil, auth.isLoggedIn {
            await auth.refreshProfile()
        }
        guard let uid = auth.profile?.userId, let cookie = auth.cookie else {
            errorText = "无法获取账号信息，请稍后重试"
            return
        }

        do {
            playlists = try await NeteaseAPI().userPlaylists(uid: uid, cookie: cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct PlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PlaylistCover(urlString: playlist.coverImgUrl)

            Text(playlist.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text("\(playlist.trackCount ?? 0) 首")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaylistCover: View {
    let urlString: String?

    var body: some View {
        Color(.tertiarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else if phase.error != nil {
                            placeholder
                        } else {
                            ZStack {
                                Color(.tertiarySystemFill)
                                ProgressView()
                            }
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
