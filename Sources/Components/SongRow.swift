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
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(song: song)
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

    private func toggleLike() async {
        guard !isLikeBusy else { return }
        isLikeBusy = true
        defer { isLikeBusy = false }
        // 失败时 PlayerStore 会自动回滚收藏状态
        try? await player.toggleLike(songId: song.id)
    }
}
