import SwiftUI

/// 全部歌手（按地区筛选）
struct ArtistListView: View {
    @EnvironmentObject private var auth: AuthStore

    private let areas: [(id: String, name: String)] = [
        ("-1", "全部"),
        ("7", "华语"),
        ("96", "欧美"),
        ("8", "日本"),
        ("16", "韩国")
    ]

    private let pageSize = 60
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    @State private var area = "-1"
    @State private var artists: [ArtistSummary] = []
    @State private var offset = 0
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                chips

                if isLoading && artists.isEmpty {
                    ProgressView("正在加载歌手…")
                        .padding(.top, 60)
                } else if let errorMessage, artists.isEmpty {
                    VStack(spacing: 10) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") {
                            Task { await reload() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.splayerAccent)
                    }
                    .padding(30)
                } else if artists.isEmpty {
                    ContentUnavailableView("暂无歌手", systemImage: "person.2")
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(artists) { artist in
                            NavigationLink {
                                ArtistDetailView(artist: artist)
                            } label: {
                                card(for: artist)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    if canLoadMore {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            HStack(spacing: 6) {
                                if isLoadingMore {
                                    ProgressView()
                                }
                                Text(isLoadingMore ? "加载中…" : "加载更多")
                                    .font(.footnote)
                            }
                            .padding(.vertical, 8)
                        }
                        .disabled(isLoadingMore)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle("全部歌手")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if artists.isEmpty {
                await reload()
            }
        }
        .onChange(of: area) { _, _ in
            Task { await reload() }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(areas.indices, id: \.self) { index in
                    let item = areas[index]
                    Button {
                        area = item.id
                    } label: {
                        Text(item.name)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                area == item.id
                                    ? Color.splayerAccent.opacity(0.18)
                                    : Color.secondary.opacity(0.1),
                                in: Capsule()
                            )
                            .foregroundStyle(area == item.id ? Color.splayerAccent : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func card(for artist: ArtistSummary) -> some View {
        VStack(spacing: 6) {
            CoverImage(urlString: artist.picUrl, size: 90, cornerRadius: 45)

            Text(artist.name)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await NeteaseAPI().artistList(
                area: area,
                limit: pageSize,
                offset: 0,
                cookie: auth.cookie
            )
            artists = result
            offset = result.count
            canLoadMore = result.count >= pageSize
        } catch {
            artists = []
            canLoadMore = false
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await NeteaseAPI().artistList(
                area: area,
                limit: pageSize,
                offset: offset,
                cookie: auth.cookie
            )
            artists.append(contentsOf: result)
            offset += result.count
            canLoadMore = result.count >= pageSize
        } catch {
            canLoadMore = false
        }
    }
}
