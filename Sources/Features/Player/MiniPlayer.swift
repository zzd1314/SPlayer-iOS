import SwiftUI

/// 悬浮胶囊迷你播放条：封面 + 歌名/歌词 + 控制
struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerStore
    @AppStorage("showLyricInBar") private var showLyricInBar = true
    @AppStorage("followCoverColor") private var followCoverColor = true

    @State private var showFullPlayer = false

    var body: some View {
        if let song = player.currentSong {
            HStack(spacing: 10) {
                CoverImage(urlString: song.albumPicUrl, size: 40, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song.name)
                        .font(.subheadline.weight(.semibold))
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
                        .font(.system(size: 19, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await player.next() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 34, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.02))
                    }
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        Capsule()
                            .fill(accent)
                            .frame(width: geo.size.width * player.progressFraction)
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 22)
                .padding(.top, 1)
                .allowsHitTesting(false)
            }
            .contentShape(Capsule(style: .continuous))
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
