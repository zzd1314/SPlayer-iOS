import SwiftUI

/// 全部排行榜列表
struct RankListView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        List {
            ForEach(playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(playlist: playlist)
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(urlString: playlist.coverImgUrl, size: 52, cornerRadius: 10)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(playlist.name)
                                .font(.body)
                                .lineLimit(1)
                            Text(playlist.trackCount.map { "\($0) 首" } ?? "排行榜")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle("排行榜")
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
            if isLoading, playlists.isEmpty {
                ProgressView()
            } else if let errorText, playlists.isEmpty, !isLoading {
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

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            playlists = try await NeteaseAPI().toplists(cookie: auth.cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
