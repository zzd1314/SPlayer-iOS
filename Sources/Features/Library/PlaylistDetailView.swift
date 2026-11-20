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
    @State private var isSubscribed = false
    @State private var isSubscribing = false
    @State private var actionError: String?

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    SongRow(index: index + 1, song: song, showsLikeButton: true)
                        .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            play(song)
                        }
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await toggleSubscribe() }
                } label: {
                    Image(systemName: isSubscribed ? "checkmark.circle.fill" : "plus.circle")
                }
                .disabled(isSubscribing || !auth.isLoggedIn)
                .foregroundStyle(isSubscribed ? Color.splayerAccent : Color.primary)
                .accessibilityLabel(isSubscribed ? "取消收藏歌单" : "收藏歌单")
            }
            if let url = playlist.shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
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

        let api = NeteaseAPI()

        do {
            songs = try await api.playlistTracks(id: playlist.id, cookie: auth.cookie)
        } catch {
            errorText = error.localizedDescription
        }

        if let subscribed = try? await api.playlistSubscribed(id: playlist.id, cookie: auth.cookie) {
            isSubscribed = subscribed
        }
    }

    private func toggleSubscribe() async {
        guard !isSubscribing, let cookie = auth.cookie else { return }
        isSubscribing = true
        defer { isSubscribing = false }

        let target = !isSubscribed
        isSubscribed = target
        do {
            try await NeteaseAPI().setPlaylistSubscribed(id: playlist.id, subscribe: target, cookie: cookie)
        } catch {
            isSubscribed = !target
            actionError = error.localizedDescription
        }
    }
}
