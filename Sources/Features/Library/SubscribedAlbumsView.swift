import SwiftUI

/// 已收藏专辑：网格展示，支持取消收藏
struct SubscribedAlbumsView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var albums: [AlbumSummary] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?
    @State private var actionError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                ForEach(albums) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        AlbumGridCard(album: album)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await unsubscribe(album) }
                        } label: {
                            Label("取消收藏", systemImage: "heart.slash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("收藏专辑")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
        }
        .task {
            if !loadedOnce {
                await load()
            }
        }
        .overlay {
            if isLoading, albums.isEmpty {
                ProgressView()
            } else if let errorText, albums.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
            } else if loadedOnce, albums.isEmpty, !isLoading {
                ContentUnavailableView("暂无收藏专辑", systemImage: "square.stack")
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

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        guard let cookie = auth.cookie else {
            errorText = "请先登录后查看收藏专辑"
            return
        }

        do {
            albums = try await NeteaseAPI().subscribedAlbums(cookie: cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func unsubscribe(_ album: AlbumSummary) async {
        guard let cookie = auth.cookie else { return }
        do {
            try await NeteaseAPI().setAlbumSubscribed(id: album.id, subscribe: false, cookie: cookie)
            albums.removeAll { $0.id == album.id }
        } catch {
            actionError = error.localizedDescription
        }
    }
}
