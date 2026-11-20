import SwiftUI

/// 歌单详情：封面信息 + 歌曲列表
struct PlaylistDetailView: View {
    let playlist: Playlist

    @EnvironmentObject private var auth: AuthStore

    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                header
            }

            Section {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    SongRow(index: index + 1, song: song)
                }
            }
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if songs.isEmpty {
                await load()
            }
        }
        .overlay {
            if isLoading && songs.isEmpty {
                ProgressView()
            }
        }
        .overlay {
            if let errorText, songs.isEmpty, !isLoading {
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
        HStack(alignment: .top, spacing: 12) {
            CoverImage(urlString: playlist.coverImgUrl, size: 84, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)
                if let creator = playlist.creator?.nickname {
                    Text(creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(songs.isEmpty ? (playlist.trackCount ?? 0) : songs.count) 首")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            songs = try await NeteaseAPI().playlistTracks(id: playlist.id, cookie: auth.cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
