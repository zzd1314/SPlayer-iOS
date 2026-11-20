import SwiftUI

/// 我关注的歌手列表
struct FollowedArtistsView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var artists: [ArtistSummary] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                ContentUnavailableView(
                    "未登录",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("登录后可查看关注的歌手")
                )
            } else {
                artistList
            }
        }
        .navigationTitle("关注歌手")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var artistList: some View {
        List {
            Section {
                ForEach(artists) { artist in
                    NavigationLink {
                        ArtistDetailView(artist: artist)
                    } label: {
                        FollowedArtistRow(artist: artist)
                    }
                }
            } header: {
                if !artists.isEmpty {
                    Text("\(artists.count) 位歌手")
                }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .task {
            if !loadedOnce {
                await load()
            }
        }
        .refreshable {
            await load()
        }
        .overlay {
            if isLoading, artists.isEmpty {
                ProgressView()
            } else if let errorText, artists.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
            } else if loadedOnce, artists.isEmpty, !isLoading {
                ContentUnavailableView(
                    "还没有关注的歌手",
                    systemImage: "person.2",
                    description: Text("在歌手详情页点击「关注」即可")
                )
            }
        }
    }

    private func load() async {
        guard !isLoading, let cookie = auth.cookie else { return }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            artists = try await NeteaseAPI().subscribedArtists(cookie: cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct FollowedArtistRow: View {
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
