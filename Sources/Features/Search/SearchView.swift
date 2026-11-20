import SwiftUI

/// 搜索：歌曲搜索（/cloudsearch?type=1）
struct SearchView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var query = ""
    @State private var songs: [Song] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var lastQuery: String?

    var body: some View {
        NavigationStack {
            Group {
                if songs.isEmpty {
                    if isSearching {
                        ProgressView("搜索中…")
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
                    } else if let lastQuery {
                        ContentUnavailableView.search(text: lastQuery)
                    } else {
                        ContentUnavailableView(
                            "搜索",
                            systemImage: "magnifyingglass",
                            description: Text("输入歌曲名或歌手开始搜索")
                        )
                    }
                } else {
                    List {
                        Section {
                            ForEach(songs) { song in
                                Button {
                                    play(song)
                                } label: {
                                    SongRow(index: nil, song: song)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                            }
                        } header: {
                            Text("找到 \(songs.count) 首歌曲")
                        }
                    }
                    .listStyle(.plain)
                    .adaptiveListBackground()
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $query, prompt: "歌曲 / 歌手")
            .onSubmit(of: .search) {
                Task { await search() }
            }
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
        }
    }

    private func play(_ song: Song) {
        Task {
            if AppSettings.searchPlayBehavior == "current" {
                await player.play([song], startAt: 0)
            } else {
                await player.play(song: song, in: songs)
            }
        }
    }

    private func search() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !isSearching else { return }

        isSearching = true
        errorText = nil
        lastQuery = keyword
        defer { isSearching = false }

        do {
            songs = try await NeteaseAPI().searchSongs(keywords: keyword, cookie: auth.cookie)
        } catch {
            songs = []
            errorText = error.localizedDescription
        }
    }
}
