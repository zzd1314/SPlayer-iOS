import SwiftUI

/// 搜索：歌曲搜索（/cloudsearch?type=1）
struct SearchView: View {
    @EnvironmentObject private var auth: AuthStore

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
                        ForEach(songs) { song in
                            SongRow(index: nil, song: song)
                        }
                    }
                }
            }
            .navigationTitle("搜索")
            .searchable(text: $query, prompt: "歌曲 / 歌手")
            .onSubmit(of: .search) {
                Task { await search() }
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
