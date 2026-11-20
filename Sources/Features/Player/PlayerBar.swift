import SwiftUI

/// 桌面版式底部播放栏：左歌曲信息、中控制与进度、右音质/队列
/// iPhone 使用同款风格的精简条，点击展开全屏播放页
struct PlayerBar: View {
    @EnvironmentObject private var player: PlayerStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("showLyricInBar") private var showLyricInBar = true
    @AppStorage("audioLevel") private var audioLevel = "exhigh"
    @AppStorage("followCoverColor") private var followCoverColor = true

    @State private var showFullPlayer = false
    @State private var activeSheet: PlayerBarSheet?
    @State private var dragTime: TimeInterval?

    private enum PlayerBarSheet: String, Identifiable {
        case queue
        case options
        var id: String { rawValue }
    }

    private var accent: Color {
        followCoverColor ? (player.coverAccent ?? .splayerAccent) : .splayerAccent
    }

    var body: some View {
        Group {
            if let song = player.currentSong {
                if horizontalSizeClass == .regular {
                    regularBar(song: song)
                } else {
                    compactBar(song: song)
                }
            }
        }
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .queue:
                PlayQueueView()
                    .presentationDetents([.medium, .large])
            case .options:
                PlayerOptionsSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - iPad / 宽屏整条

    private func regularBar(song: Song) -> some View {
        HStack(spacing: 18) {
            trackInfo(song: song)
                .frame(width: 248, alignment: .leading)

            VStack(spacing: 1) {
                transportRow
                progressRow
            }
            .frame(maxWidth: .infinity)

            rightControls
        }
        .padding(.horizontal, 18)
        .padding(.top, 9)
        .padding(.bottom, 7)
    }

    private func trackInfo(song: Song) -> some View {
        HStack(spacing: 11) {
            CoverImage(urlString: song.albumPicUrl, size: 46, cornerRadius: 7)

            VStack(alignment: .leading, spacing: 2) {
                Text(song.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(secondaryText(song: song))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button {
                Task { try? await player.toggleLikeCurrent() }
            } label: {
                Image(systemName: player.isCurrentSongLiked ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(player.isCurrentSongLiked ? accent : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isCurrentSongLiked ? "取消收藏" : "收藏")
        }
        .contentShape(Rectangle())
        .onTapGesture { showFullPlayer = true }
    }

    private var transportRow: some View {
        HStack(spacing: 22) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(player.isShuffleEnabled ? accent : Color.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("随机播放")

            Button {
                Task { await player.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一首")

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 33, weight: .regular))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一首")

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? Color.secondary : accent)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.repeatMode.title)
        }
        .foregroundStyle(Color.primary.opacity(0.82))
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            Text(format(dragTime ?? player.currentTime))
                .frame(width: 36, alignment: .trailing)
            Slider(
                value: Binding(
                    get: { dragTime ?? player.currentTime },
                    set: { dragTime = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    guard !editing, let time = dragTime else { return }
                    player.seek(to: time)
                    dragTime = nil
                }
            )
            .controlSize(.mini)
            .tint(accent)
            Text(format(player.duration))
                .frame(width: 36, alignment: .leading)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var rightControls: some View {
        HStack(spacing: 12) {
            Button {
                activeSheet = .options
            } label: {
                Text(qualityLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放音质")

            if player.playbackRate != 1 {
                Button {
                    activeSheet = .options
                } label: {
                    Text(rateLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                activeSheet = .queue
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放队列")

            Button {
                activeSheet = .options
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多播放选项")
        }
        .foregroundStyle(.secondary)
        .frame(width: 168, alignment: .trailing)
    }

    // MARK: - iPhone 精简条

    private func compactBar(song: Song) -> some View {
        HStack(spacing: 10) {
            CoverImage(urlString: song.albumPicUrl, size: 40, cornerRadius: 7)

            VStack(alignment: .leading, spacing: 1) {
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
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .topLeading) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.07))
                    Rectangle()
                        .fill(accent)
                        .frame(width: geo.size.width * player.progressFraction)
                }
            }
            .frame(height: 2)
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { showFullPlayer = true }
    }

    // MARK: - 文案

    private var qualityLabel: String {
        switch audioLevel {
        case "standard": return "LQ"
        case "higher": return "SQ"
        case "exhigh": return "HQ"
        case "lossless": return "Lossless"
        case "hires": return "Hi-Res"
        default: return "HQ"
        }
    }

    private var rateLabel: String {
        String(format: "%gx", Double(player.playbackRate))
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

    private func format(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
