import SwiftUI

/// 底部迷你播放条：进度线 + 封面 + 歌名/歌词 + 控制
struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerStore
    @AppStorage("showLyricInBar") private var showLyricInBar = true
    @AppStorage("followCoverColor") private var followCoverColor = true

    @State private var showFullPlayer = false

    var body: some View {
        if let song = player.currentSong {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Color.splayerAccent.opacity(0.16)
                        Rectangle()
                            .fill(accent)
                            .frame(width: geo.size.width * player.progressFraction)
                    }
                }
                .frame(height: 2)

                HStack(spacing: 10) {
                    CoverImage(urlString: song.albumPicUrl, size: 44, cornerRadius: 7)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(secondaryText(song: song))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await player.next() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 34, height: 38)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                if player.currentSong != nil {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 0.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                showFullPlayer = true
            }
            .fullScreenCover(isPresented: $showFullPlayer) {
                FullPlayerView()
            }
        }
    }

    private var accent: Color {
        followCoverColor ? (player.coverAccent ?? .splayerAccent) : .splayerAccent
    }

    private func secondaryText(song: Song) -> String {
        if let error = player.errorText, !error.isEmpty {
            return error
        }
        if showLyricInBar, let line = player.currentLyricLine,
           !line.text.trimmingCharacters(in: .whitespaces).isEmpty {
            return line.text
        }
        return song.artistText
    }
}
