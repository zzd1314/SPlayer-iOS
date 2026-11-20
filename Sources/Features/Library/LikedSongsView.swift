import SwiftUI

/// 我喜欢的音乐：/likelist + /song/detail
struct LikedSongsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        play(song)
                    } label: {
                        SongRow(index: index + 1, song: song)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                }

                if songs.isEmpty, loadedOnce, errorText == nil, !isLoading {
                    Text("还没有收藏的歌曲")
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
        .navigationTitle("我喜欢的音乐")
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

        guard let uid = player.userID ?? auth.profile?.userId, let cookie = auth.cookie else {
            errorText = "无法获取账号信息，请稍后重试"
            loadedOnce = true
            return
        }

        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            let api = NeteaseAPI()
            let ids = try await api.likeList(uid: uid, cookie: cookie)
            songs = try await api.songDetails(ids: ids, cookie: cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
