import SwiftUI

/// 我的云盘（仅展示可播放的云端歌曲）
struct CloudMusicView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        List {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(index: index + 1, song: song, showsLikeButton: true)
                    .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await player.play(song: song, in: songs) }
                    }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle("我的云盘")
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
        .refreshable {
            await load()
        }
        .task {
            if !loadedOnce {
                await load()
            }
        }
        .overlay {
            if isLoading, songs.isEmpty {
                ProgressView()
            } else if let errorText, songs.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
            } else if loadedOnce, songs.isEmpty, !isLoading {
                ContentUnavailableView(
                    "云盘暂无歌曲",
                    systemImage: "cloud",
                    description: Text("在网易云客户端上传音乐后会自动同步到这里")
                )
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        guard let cookie = auth.cookie else {
            errorText = "请先登录"
            return
        }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            songs = try await NeteaseAPI().cloudSongs(cookie: cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
