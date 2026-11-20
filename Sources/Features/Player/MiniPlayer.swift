import SwiftUI

/// 底部迷你播放条（TabBar 上方）
struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var showFullPlayer = false

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: 10) {
                CoverImage(urlString: song.albumPicUrl, size: 40, cornerRadius: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(song.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(player.errorText ?? song.artistText)
                        .font(.caption2)
                        .foregroundStyle(player.errorText == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await player.next() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.footnote)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Divider() }
            .contentShape(Rectangle())
            .onTapGesture { showFullPlayer = true }
            .sheet(isPresented: $showFullPlayer) {
                FullPlayerView()
            }
        }
    }
}
