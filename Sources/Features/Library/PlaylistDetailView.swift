import SwiftUI

/// 歌单详情：封面信息 + 歌曲列表
struct PlaylistDetailView: View {
    let playlist: Playlist

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    Button {
                        play(song)
                    } label: {
                        SongRow(index: index + 1, song: song)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                }

                if songs.isEmpty, loadedOnce, errorText == nil {
                    Text("暂无歌曲")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            } header: {
                if !songs.isEmpty {
                    Text("\(songs.count) 首歌曲")
                }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !songs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await player.play(songs, startAt: 0) }
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                }
            }
        }
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
        HStack(alignment: .top, spacing: 14) {
            CoverImage(urlString: playlist.coverImgUrl, size: 96, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 5) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(2)
                if let creator = playlist.creator?.nickname {
                    Text(creator)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(songs.isEmpty ? (playlist.trackCount ?? 0) : songs.count) 首")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func play(_ song: Song) {
        Task {
            if AppSettings.songListPlayBehavior == "current" {
                await player.play([song], startAt: 0)
            } else {
                await player.play(song: song, in: songs)
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
            songs = try await NeteaseAPI().playlistTracks(id: playlist.id, cookie: auth.cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
