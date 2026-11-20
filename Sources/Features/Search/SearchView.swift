import SwiftUI

/// 搜索分类
private enum SearchCategory: String, CaseIterable, Identifiable {
    case songs = "单曲"
    case artists = "歌手"
    case albums = "专辑"
    case playlists = "歌单"
    case mvs = "MV"

    var id: String { rawValue }
}

/// 搜索：单曲 / 歌手 / 专辑 / 歌单 / MV（/cloudsearch type=1/100/10/1000/1004）
struct SearchView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var query = ""
    @State private var category: SearchCategory = .songs
    @State private var songs: [Song] = []
    @State private var artists: [ArtistSummary] = []
    @State private var albums: [AlbumSummary] = []
    @State private var playlists: [Playlist] = []
    @State private var mvs: [MVSummary] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var lastQuery: String?
    @State private var suggestions: [String] = []
    @State private var hotItems: [HotSearchResponse.Item] = []
    @State private var history: [String] = AppSettings.searchHistory
    @State private var isLoadingHot = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("搜索分类", selection: $category) {
                    ForEach(SearchCategory.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                content
            }
            .navigationTitle("搜索")
            .searchable(text: $query, prompt: "歌曲 / 歌手 / 专辑 / 歌单 / MV")
            .searchSuggestions {
                ForEach(suggestions, id: \.self) { keyword in
                    Label(keyword, systemImage: "magnifyingglass")
                        .searchCompletion(keyword)
                }
            }
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .task(id: query) {
                await updateSuggestions()
            }
            .task {
                if hotItems.isEmpty {
                    await loadHot()
                }
            }
            .onChange(of: category) { _, _ in
                guard let lastQuery, !lastQuery.isEmpty else { return }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    query = lastQuery
                }
                Task { await search() }
            }
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .navigationDestination(for: ArtistSummary.self) { artist in
                ArtistDetailView(artist: artist)
            }
            .navigationDestination(for: AlbumSummary.self) { album in
                AlbumDetailView(album: album)
            }
            .toolbar {
                if category == .songs, !songs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await player.play(songs, startAt: 0) }
                        } label: {
                            Label("播放全部", systemImage: "play.fill")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if currentIsEmpty {
            if isSearching {
                ProgressView("搜索中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                ContentUnavailableView {
                    Label("搜索失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await search() }
                    }
                }
            } else if let lastQuery, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: lastQuery)
            } else if !history.isEmpty || !hotItems.isEmpty {
                discovery
            } else {
                ContentUnavailableView(
                    "搜索",
                    systemImage: "magnifyingglass",
                    description: Text("输入关键词搜索歌曲、歌手、专辑、歌单或 MV")
                )
            }
        } else {
            results
        }
    }

    /// 搜索发现：最近搜索 + 热搜榜
    private var discovery: some View {
        List {
            if !history.isEmpty {
                Section {
                    ForEach(history, id: \.self) { keyword in
                        Button {
                            applySuggestion(keyword)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(keyword)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                } header: {
                    HStack {
                        Text("最近搜索")
                        Spacer()
                        Button("清空") {
                            AppSettings.clearSearchHistory()
                            history = []
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }

            if !hotItems.isEmpty {
                Section {
                    ForEach(hotItems.indices, id: \.self) { index in
                        let item = hotItems[index]
                        Button {
                            applySuggestion(item.searchWord)
                        } label: {
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(index < 3 ? Color.splayerAccent : Color.secondary)
                                    .frame(width: 24, alignment: .trailing)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.searchWord)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    if let content = item.content, !content.isEmpty {
                                        Text(content)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Label("热搜榜", systemImage: "flame.fill")
                }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .refreshable {
            await loadHot()
        }
    }

    @ViewBuilder
    private var results: some View {
        switch category {
        case .songs:
            List {
                Section {
                    ForEach(songs) { song in
                        SongRow(index: nil, song: song, showsLikeButton: true)
                            .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                play(song)
                            }
                    }
                } header: {
                    Text("找到 \(songs.count) 首歌曲")
                }
            }
            .listStyle(.plain)
            .adaptiveListBackground()

        case .artists:
            List {
                Section {
                    ForEach(artists) { artist in
                        NavigationLink(value: artist) {
                            ArtistRow(artist: artist)
                        }
                    }
                } header: {
                    Text("找到 \(artists.count) 位歌手")
                }
            }
            .listStyle(.plain)
            .adaptiveListBackground()

        case .albums:
            List {
                Section {
                    ForEach(albums) { album in
                        NavigationLink(value: album) {
                            AlbumRow(album: album)
                        }
                    }
                } header: {
                    Text("找到 \(albums.count) 张专辑")
                }
            }
            .listStyle(.plain)
            .adaptiveListBackground()

        case .playlists:
            List {
                Section {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist) {
                            PlaylistRow(playlist: playlist)
                        }
                    }
                } header: {
                    Text("找到 \(playlists.count) 个歌单")
                }
            }
            .listStyle(.plain)
            .adaptiveListBackground()

        case .mvs:
            List {
                Section {
                    ForEach(mvs) { mv in
                        NavigationLink {
                            MVPlayerView(mv: mv)
                        } label: {
                            MVRow(mv: mv)
                        }
                    }
                } header: {
                    Text("找到 \(mvs.count) 个 MV")
                }
            }
            .listStyle(.plain)
            .adaptiveListBackground()
        }
    }

    private var currentIsEmpty: Bool {
        switch category {
        case .songs: return songs.isEmpty
        case .artists: return artists.isEmpty
        case .albums: return albums.isEmpty
        case .playlists: return playlists.isEmpty
        case .mvs: return mvs.isEmpty
        }
    }

    // MARK: - 操作

    private func play(_ song: Song) {
        Task {
            if AppSettings.searchPlayBehavior == "current" {
                await player.play([song], startAt: 0)
            } else {
                await player.play(song: song, in: songs)
            }
        }
    }

    private func applySuggestion(_ keyword: String) {
        query = keyword
        Task { await search() }
    }

    /// 输入防抖后请求搜索建议
    private func updateSuggestions() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, keyword != lastQuery else {
            suggestions = []
            return
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        suggestions = (try? await NeteaseAPI().searchSuggest(
            keywords: keyword,
            cookie: auth.cookie
        )) ?? []
    }

    private func loadHot() async {
        guard !isLoadingHot else { return }
        isLoadingHot = true
        defer { isLoadingHot = false }

        hotItems = (try? await NeteaseAPI().hotSearches(cookie: auth.cookie)) ?? []
    }

    private func search() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !isSearching else { return }

        AppSettings.addSearchHistory(keyword)
        history = AppSettings.searchHistory

        isSearching = true
        errorText = nil
        lastQuery = keyword
        let current = category
        defer { isSearching = false }

        let api = NeteaseAPI()
        let cookie = auth.cookie

        do {
            switch current {
            case .songs:
                songs = try await api.searchSongs(keywords: keyword, cookie: cookie)
            case .artists:
                artists = try await api.searchArtists(keywords: keyword, cookie: cookie)
            case .albums:
                albums = try await api.searchAlbums(keywords: keyword, cookie: cookie)
            case .playlists:
                playlists = try await api.searchPlaylists(keywords: keyword, cookie: cookie)
            case .mvs:
                mvs = try await api.searchMVs(keywords: keyword, cookie: cookie)
            }
        } catch {
            switch current {
            case .songs: songs = []
            case .artists: artists = []
            case .albums: albums = []
            case .playlists: playlists = []
            case .mvs: mvs = []
            }
            if current == category {
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - 结果行

private struct ArtistRow: View {
    let artist: ArtistSummary

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(urlString: artist.picUrl, size: 46, cornerRadius: 23)

            VStack(alignment: .leading, spacing: 3) {
                Text(artist.name)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let alias = artist.alias?.filter({ !$0.isEmpty }), !alias.isEmpty {
            parts.append(alias.joined(separator: " / "))
        }
        if let musicSize = artist.musicSize, musicSize > 0 {
            parts.append("\(musicSize) 首单曲")
        }
        if let albumSize = artist.albumSize, albumSize > 0 {
            parts.append("\(albumSize) 张专辑")
        }
        return parts.isEmpty ? "歌手" : parts.joined(separator: " · ")
    }
}

private struct AlbumRow: View {
    let album: AlbumSummary

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(urlString: album.picUrl, size: 46, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(album.name)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = [album.artistText]
        if let size = album.size, size > 0 {
            parts.append("\(size) 首")
        }
        if let year = album.publishYearText {
            parts.append(year)
        }
        return parts.joined(separator: " · ")
    }
}

private struct PlaylistRow: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(urlString: playlist.coverImgUrl, size: 46, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let creator = playlist.creator?.nickname, !creator.isEmpty {
            parts.append(creator)
        }
        if let count = playlist.trackCount, count > 0 {
            parts.append("\(count) 首")
        }
        return parts.isEmpty ? "歌单" : parts.joined(separator: " · ")
    }
}

private struct MVRow: View {
    let mv: MVSummary

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(urlString: mv.cover, size: 52, cornerRadius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(mv.name)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if let artist = mv.artistName, !artist.isEmpty {
            parts.append(artist)
        }
        if let count = mv.playCount, count > 0 {
            if count >= 10000 {
                parts.append(String(format: "%.1f 万次播放", Double(count) / 10000))
            } else {
                parts.append("\(count) 次播放")
            }
        }
        return parts.isEmpty ? "MV" : parts.joined(separator: " · ")
    }
}
