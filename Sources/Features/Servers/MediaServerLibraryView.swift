import SwiftUI

/// 媒体服务器专辑浏览
struct MediaServerLibraryView: View {
    let server: MediaServer

    @State private var albums: [MediaServerAlbum] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView {
            if isLoading && albums.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载专辑…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else if let errorMessage, albums.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task { await load(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.splayerAccent)
                }
                .padding(30)
                .frame(maxWidth: .infinity)
            } else if albums.isEmpty {
                ContentUnavailableView("暂无专辑", systemImage: "square.stack", description: Text("服务器上还没有可浏览的音乐专辑"))
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(albums) { album in
                        NavigationLink {
                            MediaServerAlbumView(server: server, album: album)
                        } label: {
                            card(for: album)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .adaptiveListBackground()
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load(force: true)
        }
        .task {
            guard !hasLoaded else { return }
            await load(force: true)
        }
    }

    private func card(for album: MediaServerAlbum) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(urlString: album.coverURL?.absoluteString, size: 150, cornerRadius: 10)

            Text(album.name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(subtitle(for: album))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitle(for album: MediaServerAlbum) -> String {
        var parts: [String] = []
        if let artist = album.artist, !artist.isEmpty {
            parts.append(artist)
        }
        if let year = album.year {
            parts.append(String(year))
        }
        return parts.isEmpty ? "未知歌手" : parts.joined(separator: " · ")
    }

    private func load(force: Bool) async {
        if isLoading { return }
        if hasLoaded && !force { return }

        isLoading = true
        errorMessage = nil
        do {
            albums = try await MediaServerClient.albums(server: server)
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
