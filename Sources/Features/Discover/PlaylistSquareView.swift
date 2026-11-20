import SwiftUI

/// 歌单广场：分类筛选 + 瀑布式加载
struct PlaylistSquareView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var categories: [String] = ["全部"]
    @State private var selectedCategory = "全部"
    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorText: String?
    @State private var hasMore = true
    @State private var offset = 0

    private let pageSize = 30
    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                categoryBar

                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(playlists) { playlist in
                        NavigationLink {
                            PlaylistDetailView(playlist: playlist)
                        } label: {
                            PlaylistCard(playlist: playlist)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if playlist.id == playlists.last?.id {
                                Task { await loadMore() }
                            }
                        }
                    }
                }

                if isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("歌单广场")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if playlists.isEmpty {
                await loadCategories()
                await reload()
            }
        }
        .overlay {
            if isLoading, playlists.isEmpty {
                ProgressView("正在加载…")
            } else if let errorText, playlists.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task {
                            await loadCategories()
                            await reload()
                        }
                    }
                }
            }
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        guard selectedCategory != category else { return }
                        selectedCategory = category
                        Task { await reload() }
                    } label: {
                        Text(category)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedCategory == category
                                    ? Color.splayerAccent
                                    : Color.secondary.opacity(0.14),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                selectedCategory == category ? Color.white : Color.primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func loadCategories() async {
        guard categories.count <= 1 else { return }
        if let names = try? await NeteaseAPI().playlistCategories(cookie: auth.cookie),
           !names.isEmpty {
            categories = ["全部"] + names
        }
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let result = try await NeteaseAPI().topPlaylists(
                category: selectedCategory,
                limit: pageSize,
                offset: 0,
                cookie: auth.cookie
            )
            playlists = result
            offset = result.count
            hasMore = result.count >= pageSize
        } catch {
            playlists = []
            hasMore = false
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await NeteaseAPI().topPlaylists(
                category: selectedCategory,
                limit: pageSize,
                offset: offset,
                cookie: auth.cookie
            )
            let existing = Set(playlists.map(\.id))
            let newItems = result.filter { !existing.contains($0.id) }
            playlists.append(contentsOf: newItems)
            offset += result.count
            hasMore = result.count >= pageSize
        } catch {
            hasMore = false
            errorText = error.localizedDescription
        }
    }
}
