import SwiftUI

/// 歌手详情：资料 + 热门歌曲 + 专辑
struct ArtistDetailView: View {
    let artist: ArtistSummary

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var detail: ArtistSummary?
    @State private var hotSongs: [Song] = []
    @State private var albums: [AlbumSummary] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    private var info: ArtistSummary {
        detail ?? artist
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
            }

            if !hotSongs.isEmpty {
                Section {
                    ForEach(Array(hotSongs.enumerated()), id: \.offset) { index, song in
                        SongRow(index: index + 1, song: song, showsLikeButton: true)
                            .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                play(song)
                            }
                    }
                } header: {
                    Text("热门歌曲")
                }
            }

            if !albums.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(albums) { album in
                                NavigationLink {
                                    AlbumDetailView(album: album)
                                } label: {
                                    ArtistAlbumCard(album: album)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } header: {
                    Text("专辑")
                }
            }

            if hotSongs.isEmpty, albums.isEmpty, loadedOnce, errorText == nil, !isLoading {
                Text("暂无内容")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle(artist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let url = artist.shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: url) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
            if !hotSongs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await player.play(hotSongs, startAt: 0) }
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
            if isLoading, hotSongs.isEmpty, albums.isEmpty {
                ProgressView()
            }
        }
        .overlay {
            if let errorText, hotSongs.isEmpty, albums.isEmpty, !isLoading {
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
            CoverImage(urlString: info.picUrl, size: 92, cornerRadius: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(info.name)
                    .font(.headline)
                    .lineLimit(2)

                if let alias = info.alias?.filter({ !$0.isEmpty }), !alias.isEmpty {
                    Text(alias.joined(separator: " / "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let statsText = statsText {
                    Text(statsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var statsText: String? {
        var parts: [String] = []
        if let musicSize = info.musicSize, musicSize > 0 {
            parts.append("\(musicSize) 首单曲")
        }
        if let albumSize = info.albumSize, albumSize > 0 {
            parts.append("\(albumSize) 张专辑")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func play(_ song: Song) {
        Task {
            if AppSettings.songListPlayBehavior == "current" {
                await player.play([song], startAt: 0)
            } else {
                await player.play(song: song, in: hotSongs)
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
        let cookie = auth.cookie

        do {
            let result = try await api.artistDetail(id: artist.id, cookie: cookie)
            detail = result.artist
            hotSongs = result.hotSongs
        } catch {
            errorText = error.localizedDescription
        }

        albums = (try? await api.artistAlbums(id: artist.id, cookie: cookie)) ?? []
    }
}

private struct ArtistAlbumCard: View {
    let album: AlbumSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(urlString: album.picUrl, size: 120, cornerRadius: 12)

            Text(album.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 120, alignment: .leading)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let year = album.publishYearText {
            parts.append(year)
        }
        if let size = album.size, size > 0 {
            parts.append("\(size) 首")
        }
        return parts.isEmpty ? "专辑" : parts.joined(separator: " · ")
    }
}
