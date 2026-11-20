import SwiftUI

/// 我喜欢的音乐：/likelist + /song/detail
struct LikedSongsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    /// 我喜欢的音乐排序方式
    private enum SortOption: String, CaseIterable, Identifiable {
        case defaultOrder
        case name
        case artist
        case album
        case duration

        var id: String { rawValue }

        var title: String {
            switch self {
            case .defaultOrder: return "收藏时间（最新在前）"
            case .name: return "歌曲名"
            case .artist: return "歌手"
            case .album: return "专辑"
            case .duration: return "时长"
            }
        }
    }

    @AppStorage("likedSongsSort") private var sortRaw = SortOption.defaultOrder.rawValue

    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section {
                ForEach(Array(sortedSongs.enumerated()), id: \.element.id) { index, song in
                    SongRow(index: index + 1, song: song, showsLikeButton: true)
                        .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            play(song)
                        }
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
                    Menu {
                        Picker("排序方式", selection: sortBinding) {
                            ForEach(SortOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Label("排序", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await player.play(sortedSongs, startAt: 0) }
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

    private var sortBinding: Binding<SortOption> {
        Binding(
            get: { SortOption(rawValue: sortRaw) ?? .defaultOrder },
            set: { sortRaw = $0.rawValue }
        )
    }

    /// 按当前选择排序；默认保持接口返回的收藏时间顺序
    private var sortedSongs: [Song] {
        switch SortOption(rawValue: sortRaw) ?? .defaultOrder {
        case .defaultOrder:
            return songs
        case .name:
            return songs.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .artist:
            return songs.sorted { lhs, rhs in
                let l = lhs.artists.first?.name ?? ""
                let r = rhs.artists.first?.name ?? ""
                let result = l.localizedStandardCompare(r)
                if result == .orderedSame {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return result == .orderedAscending
            }
        case .album:
            return songs.sorted { lhs, rhs in
                let l = lhs.albumName ?? ""
                let r = rhs.albumName ?? ""
                let result = l.localizedStandardCompare(r)
                if result == .orderedSame {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return result == .orderedAscending
            }
        case .duration:
            return songs.sorted { $0.duration < $1.duration }
        }
    }

    private func play(_ song: Song) {
        Task {
            if AppSettings.songListPlayBehavior == "current" {
                await player.play([song], startAt: 0)
            } else {
                await player.play(song: song, in: sortedSongs)
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
            let allIds = try await api.likeList(uid: uid, cookie: cookie)
            let allSet = Set(allIds)
            var seen = Set<Int>()
            var result: [Song] = []

            // 与桌面端一致：使用歌单详情 tracks 的数组顺序（最新收藏在前）
            let detail: (tracks: [Song], trackIds: [Int]) =
                (try? await api.likedPlaylist(uid: uid, cookie: cookie)) ?? (tracks: [], trackIds: [])
            for song in detail.tracks where allSet.contains(song.id) {
                if seen.insert(song.id).inserted { result.append(song) }
            }
            // tracks 未覆盖的曲目（超过单次返回上限时）按 trackIds 顺序补齐
            let missingIds = detail.trackIds.filter { allSet.contains($0) && !seen.contains($0) }
            if !missingIds.isEmpty {
                let fetched = try await api.songDetails(ids: missingIds, cookie: cookie)
                let byId = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for id in missingIds {
                    if let song = byId[id], seen.insert(id).inserted { result.append(song) }
                }
            }
            // 兜底：歌单详情不可用时回退到 likelist 顺序
            if result.isEmpty {
                let fetched = try await api.songDetails(ids: allIds, cookie: cookie)
                let byId = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                result = allIds.compactMap { byId[$0] }
            }
            songs = result
        } catch {
            errorText = error.localizedDescription
        }
    }
}
