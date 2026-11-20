import SwiftUI

/// 歌曲行：封面 + 序号（可选）+ 歌名 + 歌手 · 专辑（可选收藏按钮）
struct SongRow: View {
    let index: Int?
    let song: Song
    /// 是否显示行内收藏按钮
    var showsLikeButton = false

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var isLikeBusy = false
    @State private var showAddToPlaylist = false
    @State private var isDownloading = false
    @State private var downloaded = false
    @State private var downloadError: String?

    var body: some View {
        HStack(spacing: 10) {
            if let index {
                Text("\(index)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }

            CoverImage(urlString: song.albumPicUrl, size: 42, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.name)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if downloaded {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("已下载")
            }

            if showsLikeButton {
                Button {
                    Task { await toggleLike() }
                } label: {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.footnote)
                        .foregroundStyle(isLiked ? Color.splayerAccent : Color.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(isLikeBusy || !auth.isLoggedIn)
                .accessibilityLabel(isLiked ? "取消收藏" : "收藏")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if auth.isLoggedIn {
                Button {
                    showAddToPlaylist = true
                } label: {
                    Label("添加到歌单", systemImage: "text.badge.plus")
                }
            }

            if song.id > 0 {
                if downloaded {
                    Button(role: .destructive) {
                        DownloadStore.remove(song.id)
                        downloaded = false
                    } label: {
                        Label("删除下载", systemImage: "trash")
                    }
                } else {
                    Button {
                        Task { await download() }
                    } label: {
                        Label(isDownloading ? "下载中…" : "下载", systemImage: "arrow.down.circle")
                    }
                    .disabled(isDownloading)
                }
            }
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
        }
        .onAppear {
            downloaded = DownloadStore.isDownloaded(song.id)
        }
        .alert("下载失败", isPresented: Binding(
            get: { downloadError != nil },
            set: { if !$0 { downloadError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(downloadError ?? "")
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if !song.artistText.isEmpty {
            parts.append(song.artistText)
        }
        if let album = song.albumName, !album.isEmpty {
            parts.append(album)
        }
        return parts.joined(separator: " · ")
    }

    private var isLiked: Bool {
        player.likedSongIds.contains(song.id)
    }

    private func download() async {
        guard !isDownloading, song.id > 0 else { return }
        isDownloading = true
        defer { isDownloading = false }

        do {
            try await DownloadStore.download(
                song,
                quality: AppSettings.audioLevel,
                cookie: auth.cookie
            )
            downloaded = true
        } catch {
            downloadError = error.localizedDescription
        }
    }

    private func toggleLike() async {
        guard !isLikeBusy else { return }
        isLikeBusy = true
        defer { isLikeBusy = false }
        // 失败时 PlayerStore 会自动回滚收藏状态
        try? await player.toggleLike(songId: song.id)
    }
}
