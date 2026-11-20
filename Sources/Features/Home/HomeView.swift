import SwiftUI

/// 首页：每日推荐 / 推荐歌单 / 排行榜
struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore
    @EnvironmentObject private var router: ShellRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var dailySongs: [Song] = []
    @State private var playlists: [Playlist] = []
    @State private var playlistPool: [Playlist] = []
    @State private var isShufflingPlaylists = false
    @State private var toplists: [Playlist] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack(path: router.binding(for: .home)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greeting
                    statsRow
                    if !player.recentSongs.isEmpty {
                        recentSection
                    }
                    fmEntry
                    discoverSection

                    if !dailySongs.isEmpty {
                        dailySection
                    }
                    if !playlists.isEmpty {
                        playlistSection
                    }
                    if !toplists.isEmpty {
                        toplistSection
                    }
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
            }
            .refreshable {
                await load(force: true)
            }
            .task {
                await load(force: false)
            }
            .overlay {
                if isLoading, dailySongs.isEmpty, playlists.isEmpty, toplists.isEmpty {
                    ProgressView("正在加载…")
                }
            }
            .overlay {
                if let errorText, !isLoading, dailySongs.isEmpty, playlists.isEmpty, toplists.isEmpty {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(errorText)
                    } actions: {
                        Button("重试") {
                            Task { await load(force: true) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 顶部问候

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(timeGreeting)，\(auth.profile?.nickname ?? "音乐爱好者")")
                .font(.system(size: horizontalSizeClass == .regular ? 32 : 26, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text("今天想听点什么？")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 数据概览

    private var statsRow: some View {
        HStack(spacing: 12) {
            NavigationLink {
                RecentPlaysView()
            } label: {
                statCard(
                    icon: "clock.arrow.circlepath",
                    tint: .blue,
                    value: "\(player.recentSongs.count)",
                    title: "最近播放",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                LikedSongsView()
            } label: {
                statCard(
                    icon: "heart.fill",
                    tint: .pink,
                    value: "\(player.likedSongIds.count)",
                    title: "我喜欢的音乐",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)

            if horizontalSizeClass == .regular {
                statCard(
                    icon: "music.note.list",
                    tint: .splayerAccent,
                    value: "\(playlists.count)",
                    title: "推荐歌单"
                )
            }
        }
    }

    private func statCard(icon: String, tint: Color, value: String, title: String, showsChevron: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .appCardBackground(cornerRadius: 14)
    }

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好"
        case 12..<18: return "下午好"
        default: return "晚上好"
        }
    }

    // MARK: - 私人 FM 入口

    private var fmEntry: some View {
        NavigationLink {
            PersonalFMView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "radio.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.splayerAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.splayerAccent.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("私人 FM")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("根据你的口味不间断推荐")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .appCardBackground(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 发现入口

    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("发现", systemImage: "sparkles")
                .font(.title3.weight(.semibold))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                discoverCard(title: "排行榜", icon: "chart.bar.fill", tint: .orange) {
                    RankListView()
                }
                discoverCard(title: "歌单广场", icon: "square.grid.2x2.fill", tint: .blue) {
                    PlaylistSquareView()
                }
                discoverCard(title: "新歌速递", icon: "music.note.list", tint: .green) {
                    NewSongsView()
                }
                discoverCard(title: "新碟上架", icon: "opticaldisc.fill", tint: .purple) {
                    NewAlbumsView()
                }
                discoverCard(title: "播客电台", icon: "radio", tint: .pink) {
                    PodcastListView()
                }
                discoverCard(title: "全部歌手", icon: "person.2.fill", tint: .indigo) {
                    ArtistListView()
                }
                discoverCard(title: "云村动态", icon: "text.bubble.fill", tint: .teal) {
                    EventFeedView()
                }
            }
        }
    }

    private func discoverCard<Destination: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(
                        tint.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(10)
            .appCardBackground(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 反复聆听

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("反复聆听", systemImage: "clock.arrow.circlepath")
                .font(.title3.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(player.recentSongs.prefix(10))) { song in
                        Button {
                            play(song, in: player.recentSongs)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                CoverImage(urlString: song.albumPicUrl, size: 112, cornerRadius: 10)
                                Text(song.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Text(song.artistText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 112, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 每日推荐

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("每日推荐", systemImage: "calendar")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        dailySongs.shuffle()
                    }
                } label: {
                    Label("换一批", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.splayerAccent)

                Button {
                    Task { await player.play(dailySongs, startAt: 0) }
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.splayerAccent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(dailySongs.prefix(12).enumerated()), id: \.element.id) { index, song in
                        Button {
                            play(song, in: dailySongs)
                        } label: {
                            DailySongCard(index: index + 1, song: song)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 推荐歌单

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("专属歌单", systemImage: "square.stack.fill")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    Task { await shufflePlaylists() }
                } label: {
                    Label("换一批", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.splayerAccent)
                .disabled(isShufflingPlaylists)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(playlists) { playlist in
                        NavigationLink(value: playlist) {
                            HomePlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 排行榜

    private var toplistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("排行榜", systemImage: "chart.bar.fill")
                .font(.title3.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(toplists) { playlist in
                        NavigationLink(value: playlist) {
                            HomeToplistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 操作

    private func play(_ song: Song, in songs: [Song]) {
        Task {
            await player.play(song: song, in: songs)
        }
    }

    private func load(force: Bool) async {
        guard !isLoading else { return }
        if loadedOnce, !force { return }

        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        let api = NeteaseAPI()
        let cookie = auth.cookie
        var errors: [String] = []

        do {
            dailySongs = try await api.dailyRecommendations(cookie: cookie)
        } catch {
            errors.append("每日推荐：\(error.localizedDescription)")
        }

        do {
            playlistPool = try await api.personalizedPlaylists(limit: 30, cookie: cookie)
            playlists = Array(playlistPool.prefix(12))
        } catch {
            errors.append("推荐歌单：\(error.localizedDescription)")
        }

        do {
            toplists = try await api.toplists(cookie: cookie)
        } catch {
            errors.append("排行榜：\(error.localizedDescription)")
        }

        if dailySongs.isEmpty, playlists.isEmpty, toplists.isEmpty {
            errorText = errors.first ?? "暂无内容，请稍后重试"
        }
    }

    private func shufflePlaylists() async {
        guard !isShufflingPlaylists else { return }
        isShufflingPlaylists = true
        defer { isShufflingPlaylists = false }

        if playlistPool.count < 24,
           let list = try? await NeteaseAPI().personalizedPlaylists(limit: 30, cookie: auth.cookie) {
            playlistPool = list
        }
        guard !playlistPool.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            playlists = Array(playlistPool.shuffled().prefix(12))
        }
    }
}

// MARK: - 卡片

private struct DailySongCard: View {
    let index: Int
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                CoverImage(urlString: song.albumPicUrl, size: 116, cornerRadius: 12)
                Text("\(index)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(6)
            }

            Text(song.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(song.artistText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 116, alignment: .leading)
    }
}

private struct HomePlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(urlString: playlist.coverImgUrl, size: 130, cornerRadius: 12)

            Text(playlist.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(playCountText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 130, alignment: .leading)
    }

    private var playCountText: String {
        guard let count = playlist.playCount, count > 0 else {
            return playlist.trackCount.map { "\($0) 首" } ?? "歌单"
        }
        if count >= 10_000 {
            return String(format: "%.1f 万次播放", Double(count) / 10_000)
        }
        return "\(count) 次播放"
    }
}

private struct HomeToplistCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(urlString: playlist.coverImgUrl, size: 120, cornerRadius: 12)

            Text(playlist.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(playlist.trackCount.map { "\($0) 首" } ?? "排行榜")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 120, alignment: .leading)
    }
}
