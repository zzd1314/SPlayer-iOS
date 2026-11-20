import SwiftUI

/// 专辑详情：封面信息 + 歌曲列表
struct AlbumDetailView: View {
    let album: AlbumSummary

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var detail: AlbumSummary?
    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?
    @State private var isSubscribed = false
    @State private var isSubBusy = false
    @State private var actionError: String?

    private var info: AlbumSummary {
        detail ?? album
    }

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

                if songs.isEmpty, loadedOnce, errorText == nil, !isLoading {
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
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if auth.isLoggedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await toggleSubscribe() }
                    } label: {
                        Label(
                            isSubscribed ? "取消收藏" : "收藏专辑",
                            systemImage: isSubscribed ? "checkmark.circle.fill" : "plus.circle"
                        )
                    }
                    .disabled(isSubBusy)
                    .tint(isSubscribed ? Color.splayerAccent : nil)
                }
            }
            if let url = album.shareURL {
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
            CoverImage(urlString: info.picUrl, size: 110, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 5) {
                Text(info.name)
                    .font(.headline)
                    .lineLimit(3)
                Text(info.artistText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let metaText = metaText {
                    Text(metaText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var metaText: String? {
        var parts: [String] = []
        if let date = info.publishDateText {
            parts.append(date)
        }
        let count = songs.isEmpty ? (info.size ?? 0) : songs.count
        if count > 0 {
            parts.append("\(count) 首")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
            let result = try await NeteaseAPI().albumDetail(id: album.id, cookie: auth.cookie)
            detail = result.album
            songs = result.songs
            isSubscribed = result.album.isSub ?? false
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func toggleSubscribe() async {
        guard !isSubBusy, let cookie = auth.cookie else { return }
        isSubBusy = true
        defer { isSubBusy = false }

        let target = !isSubscribed
        isSubscribed = target
        do {
            try await NeteaseAPI().setAlbumSubscribed(id: album.id, subscribe: target, cookie: cookie)
        } catch {
            isSubscribed = !target
            actionError = error.localizedDescription
        }
    }
}
