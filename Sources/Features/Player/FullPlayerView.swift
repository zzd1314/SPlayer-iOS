import SwiftUI

/// 全屏播放页
struct FullPlayerView: View {
    @EnvironmentObject private var player: PlayerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(.quaternary)
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            Spacer(minLength: 0)

            if let song = player.currentSong {
                CoverImage(urlString: song.albumPicUrl, size: 260, cornerRadius: 16)

                VStack(spacing: 6) {
                    Text(song.name)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(song.artistText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 24)

                HStack(spacing: 44) {
                    Button {
                        Task { await player.previous() }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await player.next() }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)

                if player.isLoading {
                    ProgressView()
                }

                if let error = player.errorText {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            } else {
                Text("暂无播放")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 24)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .padding()
            }
            .buttonStyle(.plain)
        }
    }
}
