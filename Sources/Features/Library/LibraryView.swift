import SwiftUI

/// 资料库：账号信息 + 我的歌单列表
struct LibraryView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let profile = auth.profile {
                    Section {
                        HStack(spacing: 12) {
                            CoverImage(urlString: profile.avatarUrl, size: 48, cornerRadius: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.nickname)
                                    .font(.headline)
                                Text("\(playlists.count) 个歌单")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("我的歌单") {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist) {
                            PlaylistRow(playlist: playlist)
                        }
                    }
                }
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

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(urlString: playlist.coverImgUrl)
            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .lineLimit(1)
                Text("\(playlist.trackCount ?? 0) 首")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
