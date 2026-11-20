import SwiftUI

/// 新碟上架
struct NewAlbumsView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var albums: [AlbumSummary] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

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
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("新碟上架")
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
            albums = try await NeteaseAPI().newAlbums(cookie: auth.cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct AlbumGridCard: View {
    let album: AlbumSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(urlString: album.picUrl, size: 150, cornerRadius: 12)

            Text(album.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(album.artistText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 150, alignment: .leading)
    }
}
