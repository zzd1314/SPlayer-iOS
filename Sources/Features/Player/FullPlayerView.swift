import SwiftUI
import UIKit

/// 全屏播放页：封面模糊背景 + 大封面 / AMLL 风格歌词 + 可拖动进度 + 播放模式
struct FullPlayerView: View {
    @EnvironmentObject private var player: PlayerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("followCoverColor") private var followCoverColor = true
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("timeFormat") private var timeFormat = TimeFormatMode.currentTotal.rawValue

    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var showComments = false
    @State private var showOptions = false
    @State private var dragTime: TimeInterval?
    @State private var hint: String?
    @State private var hintTask: Task<Void, Never>?

    private var accent: Color {
        followCoverColor ? (player.coverAccent ?? .splayerAccent) : .splayerAccent
    }

    /// iPad 等宽屏设备使用左右分栏布局
    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        ZStack {
            if isWideLayout {
                wideBackground(song: player.currentSong)
                    .ignoresSafeArea()
            } else {
                PlayerBackground(
                    song: player.currentSong,
                    blurRadius: 48,
                    dim: 0.38
                )
            }

            if let song = player.currentSong {
                if isWideLayout {
                    wideContent(song: song)
                } else {
                    content(song: song)
                }
            } else {
                emptyState
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showQueue) {
            PlayQueueView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showComments) {
            if let song = player.currentSong {
                CommentsView(resource: .song(song.id), title: song.name)
            }
        }
        .sheet(isPresented: $showOptions) {
            PlayerOptionsSheet()
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            updateIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            hintTask?.cancel()
        }
        .onChange(of: player.isPlaying) { _, _ in
            updateIdleTimer()
        }
    }

    // MARK: - 主体

    private func content(song: Song) -> some View {
        VStack(spacing: 0) {
            topBar

            mainArea(song: song)
                .padding(.top, 6)

            VStack(spacing: 4) {
                Text(song.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(song.artistText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)

            if let error = player.errorText {
                errorBar(error)
                    .padding(.top, 8)
            }

            progressSection
                .padding(.top, 14)

            controls
                .padding(.top, 4)

            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 4)
                    .transition(.opacity)
            }

            bottomBar
                .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 宽屏（iPad）布局

    /// 桌面端全屏播放页布局：左侧封面/信息/进度/控制，右侧逐行歌词，最右侧竖排工具条
    private func wideContent(song: Song) -> some View {
        GeometryReader { geo in
            let horizontalPadding: CGFloat = 46
            let leftWidth = min(max(geo.size.width * 0.33, 300), 500)
            let coverSide = min(leftWidth, max(geo.size.height * 0.52, 200))

            ZStack(alignment: .top) {
                HStack(alignment: .center, spacing: 34) {
                    wideLeftPanel(song: song, coverSide: coverSide)
                        .frame(width: leftWidth)

                    LyricsView(forceLeadingAlignment: true, plainHighlight: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.leading, horizontalPadding)
                .padding(.trailing, 92)
                .padding(.vertical, 26)

                wideTopBar
            }
            .overlay(alignment: .trailing) {
                wideToolStrip
                    .padding(.trailing, 18)
            }
            .overlay(alignment: .bottomTrailing) {
                wideCornerActions
                    .padding(.trailing, 26)
                    .padding(.bottom, 22)
            }
        }
    }

    /// 封面主色渐变背景（照搬桌面端的酒红渐变）
    private func wideBackground(song: Song?) -> some View {
        ZStack {
            Color.black

            if let song {
                coverImage(song: song)
                    .blur(radius: 70)
                    .scaleEffect(1.2)
                    .overlay(Color.black.opacity(0.2))
            }

            LinearGradient(
                colors: [
                    accent.opacity(0.82),
                    accent.opacity(0.68),
                    accent.opacity(0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.multiply)

            LinearGradient(
                colors: [Color.white.opacity(0.05), Color.clear, Color.black.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipped()
    }

    // MARK: 左栏

    private func wideLeftPanel(song: Song, coverSide: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverImage(
                urlString: player.currentCoverURL ?? song.albumPicUrl,
                size: coverSide,
                cornerRadius: 14
            )
            .shadow(color: .black.opacity(0.38), radius: 26, y: 14)

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(song.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(song.artistText)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    Task { await toggleLike() }
                } label: {
                    Image(systemName: player.isCurrentSongLiked ? "heart.fill" : "heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(player.isCurrentSongLiked ? .white : .white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    showOptions = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)

            HStack(spacing: 6) {
                if let album = song.albumName, !album.isEmpty {
                    wideTag(album)
                }
                if !player.lyricLines.isEmpty {
                    wideTag("LRC")
                }
            }
            .padding(.top, 12)

            if let error = player.errorText {
                errorBar(error)
                    .padding(.top, 10)
            }

            wideProgress
                .padding(.top, 16)

            widePlaybackControls
                .padding(.top, 20)

            wideVolumeRow
                .padding(.top, 18)
                .padding(.bottom, 2)
        }
    }

    /// 细进度条：与桌面端一致，拖动即定位
    private var wideProgress: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let ratio = player.duration > 0
                    ? min(max(currentPosition / player.duration, 0), 1)
                    : 0

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.26))
                        .frame(height: 3)
                    Capsule()
                        .fill(.white)
                        .frame(width: max(3, width * ratio), height: 3)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard player.duration > 0 else { return }
                            dragTime = min(max(Double(value.location.x / width), 0), 1) * player.duration
                        }
                        .onEnded { value in
                            guard player.duration > 0 else { return }
                            let target = min(max(Double(value.location.x / width), 0), 1) * player.duration
                            player.seek(to: target)
                            dragTime = nil
                        }
                )
            }
            .frame(height: 14)

            HStack(spacing: 10) {
                Text(prefixForLeading() + format(leadingTime))
                Spacer(minLength: 4)
                wideTag(AppSettings.audioLevelLabel)
                Spacer(minLength: 4)
                Text(prefixForTrailing() + format(trailingTime))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var widePlaybackControls: some View {
        HStack(spacing: 0) {
            Button {
                player.toggleShuffle()
                showHint(player.isShuffleEnabled ? "随机播放已开启" : "随机播放已关闭")
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(player.isShuffleEnabled ? .white : .white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)

            Button {
                Task { await player.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .frame(width: 38, height: 38)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxWidth: .infinity)

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Button {
                player.cycleRepeatMode()
                showHint(player.repeatMode.title)
            } label: {
                Image(systemName: player.repeatMode.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.55) : .white)
                    .frame(width: 34, height: 30)
                    .background {
                        if player.repeatMode != .off {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.16))
                        }
                    }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var wideVolumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))

            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                let ratio = CGFloat(player.volume)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                        .frame(height: 3)
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: max(3, width * ratio), height: 3)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            player.setVolume(Float(min(max(value.location.x / width, 0), 1)))
                        }
                )
            }
            .frame(height: 14)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: 右侧工具条

    private var wideToolStrip: some View {
        VStack(spacing: 20) {
            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
            }

            Button {
                showComments = true
            } label: {
                Image(systemName: "bubble.left")
            }

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 16, height: 1)

            Button {
                adjustPlaybackRate(by: 0.1)
            } label: {
                Image(systemName: "plus")
            }

            Text(rateLabel)
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .frame(width: 26)

            Button {
                adjustPlaybackRate(by: -0.1)
            } label: {
                Image(systemName: "minus")
            }

            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 16, height: 1)

            Button {
                showOptions = true
            } label: {
                Image(systemName: "moon.zzz")
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white.opacity(0.72))
        .buttonStyle(.plain)
    }

    private var wideCornerActions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await toggleLike() }
            } label: {
                Image(systemName: player.isCurrentSongLiked ? "heart.fill" : "heart")
                    .foregroundStyle(player.isCurrentSongLiked ? .white : .white.opacity(0.8))
            }

            Button {
                showComments = true
            } label: {
                Image(systemName: "bubble.left")
            }

            if let url = player.currentSong?.shareURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.white.opacity(0.8))
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.1), in: Capsule())
    }

    /// 顶部：中间抓手（点击收起）+ 右侧与桌面端一致的窗口按钮
    private var wideTopBar: some View {
        ZStack {
            Button {
                dismiss()
            } label: {
                Capsule()
                    .fill(.white.opacity(0.4))
                    .frame(width: 38, height: 4)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起播放页")

            HStack(spacing: 16) {
                Spacer()

                Button {
                    showQueue = true
                } label: {
                    Image(systemName: "square.grid.2x2")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }

                Button {
                    showOptions = true
                } label: {
                    Image(systemName: "minus")
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.65))
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 26)
        .padding(.top, 16)
    }

    private func adjustPlaybackRate(by delta: Float) {
        let target = min(max(player.playbackRate + delta, 0.5), 2.0)
        player.setPlaybackRate((target * 10).rounded() / 10)
        showHint("播放速度 \(rateLabel)")
    }

    @ViewBuilder
    private func coverImage(song: Song) -> some View {
        if let urlString = player.currentCoverURL ?? song.albumPicUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black
                }
            }
        } else {
            Color.black
        }
    }

    private func wideTag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.8)
            }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(player.sleepTimerLabel ?? (showLyrics ? "歌词" : "正在播放"))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func mainArea(song: Song) -> some View {
        ZStack {
            if showLyrics {
                LyricsView()
                    .transition(.opacity)
            } else {
                GeometryReader { geo in
                    let side = min(min(geo.size.width - 56, 330), max(geo.size.height - 8, 160))
                    CoverImage(urlString: player.currentCoverURL ?? song.albumPicUrl, size: side, cornerRadius: 20)
                        .shadow(color: .black.opacity(0.45), radius: 26, y: 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .transition(.opacity)

                if player.isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                showLyrics.toggle()
            }
        }
    }

    private func errorBar(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .lineLimit(2)
            Spacer(minLength: 6)
            Button("重试") {
                Task { await player.retry() }
            }
            .font(.caption.weight(.semibold))
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 进度

    private var progressSection: some View {
        VStack(spacing: 4) {
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
            .tint(accent)

            HStack {
                Text(prefixForLeading() + format(leadingTime))
                    .onTapGesture { cycleTimeFormat() }
                Spacer()
                Text(prefixForTrailing() + format(trailingTime))
                    .onTapGesture { cycleTimeFormat() }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var currentPosition: TimeInterval {
        dragTime ?? player.currentTime
    }

    private var leadingTime: TimeInterval {
        if timeFormat == TimeFormatMode.remainingTotal.rawValue {
            return max(0, player.duration - currentPosition)
        }
        return currentPosition
    }

    private var trailingTime: TimeInterval {
        switch timeFormat {
        case TimeFormatMode.remainingTotal.rawValue:
            return player.duration
        case TimeFormatMode.currentRemaining.rawValue:
            return max(0, player.duration - currentPosition)
        default:
            return player.duration
        }
    }

    private func prefixForLeading() -> String {
        timeFormat == TimeFormatMode.remainingTotal.rawValue ? "-" : ""
    }

    private func prefixForTrailing() -> String {
        timeFormat == TimeFormatMode.currentRemaining.rawValue ? "-" : ""
    }

    private func format(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func cycleTimeFormat() {
        let modes = TimeFormatMode.allCases
        guard let index = modes.firstIndex(where: { $0.rawValue == timeFormat }) else { return }
        timeFormat = modes[(index + 1) % modes.count].rawValue
    }

    // MARK: - 控制

    private var controls: some View {
        HStack(spacing: 0) {
            Button {
                player.toggleShuffle()
                showHint(player.isShuffleEnabled ? "随机播放已开启" : "随机播放已关闭")
            } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(player.isShuffleEnabled ? accent : .white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

            Button {
                Task { await player.previous() }
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            }
            .frame(width: 92)

            Button {
                Task { await player.next() }
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 58)

            Button {
                player.cycleRepeatMode()
                showHint(player.repeatMode.title)
            } label: {
                Image(systemName: player.repeatMode.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(player.repeatMode == .off ? .white.opacity(0.5) : accent)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showLyrics.toggle()
                }
            } label: {
                Label(showLyrics ? "封面" : "歌词", systemImage: showLyrics ? "photo" : "text.quote")
            }

            Spacer()

            Text(player.playbackRate == 1 ? "1x" : rateLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(player.playbackRate == 1 ? .white.opacity(0.85) : accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
                .onTapGesture { showOptions = true }

            Spacer()

            if let url = player.currentSong?.shareURL {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            Button {
                showComments = true
            } label: {
                Image(systemName: "bubble.left")
            }

            Button {
                Task { await toggleLike() }
            } label: {
                Image(systemName: player.isCurrentSongLiked ? "heart.fill" : "heart")
                    .foregroundStyle(player.isCurrentSongLiked ? accent : .white.opacity(0.85))
            }

            Button {
                showQueue = true
            } label: {
                Image(systemName: "list.bullet")
            }
        }
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.85))
        .buttonStyle(.plain)
    }

    private func toggleLike() async {
        do {
            try await player.toggleLikeCurrent()
            showHint(player.isCurrentSongLiked ? "已收藏" : "已取消收藏")
        } catch {
            showHint("操作失败：\(error.localizedDescription)")
        }
    }

    private var rateLabel: String {
        String(format: "%gx", Double(player.playbackRate))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.6))
            Text("暂无播放")
                .font(.headline)
                .foregroundStyle(.white)
            Button("返回") {
                dismiss()
            }
            .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func showHint(_ text: String) {
        hintTask?.cancel()
        withAnimation { hint = text }
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { hint = nil }
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && player.isPlaying
    }
}

// MARK: - 模糊封面背景

private struct PlayerBackground: View {
    let song: Song?
    var blurRadius: CGFloat = 48
    var dim: Double = 0.38
    /// 宽屏下右侧加深，保证歌词可读
    var trailingScrim = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let urlString = song?.albumPicUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.black
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: blurRadius)
                    .overlay(Color.black.opacity(dim))
                }

                LinearGradient(
                    colors: [Color.black.opacity(0.05), Color.black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if trailingScrim {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.34),
                            .init(color: .black.opacity(0.5), location: 0.62),
                            .init(color: .black.opacity(0.88), location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 播放选项（倍速 / 睡眠定时）

struct PlayerOptionsSheet: View {
    @EnvironmentObject private var player: PlayerStore
    @Environment(\.dismiss) private var dismiss

    private let sleepMinutes = [5, 10, 15, 30, 45, 60]

    private var rateBinding: Binding<Double> {
        Binding(
            get: { Double(player.playbackRate) },
            set: { player.setPlaybackRate(Float($0)) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("播放速度", selection: rateBinding) {
                        ForEach(AppSettings.playbackRateOptions, id: \.self) { value in
                            Text(AppSettings.playbackRateLabel(value)).tag(value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("播放速度")
                }

                Section {
                    if let label = player.sleepTimerLabel {
                        HStack {
                            Label("当前状态", systemImage: "moon.zzz.fill")
                            Spacer()
                            Text(label)
                                .foregroundStyle(.secondary)
                        }
                        Button("关闭睡眠定时", role: .destructive) {
                            player.cancelSleepTimer()
                        }
                    }

                    ForEach(sleepMinutes, id: \.self) { minutes in
                        Button("\(minutes) 分钟后暂停") {
                            player.startSleepTimer(minutes: minutes)
                        }
                    }

                    Button("播完当前歌曲后暂停") {
                        player.startSleepAtTrackEnd()
                    }
                } header: {
                    Text("睡眠定时")
                } footer: {
                    Text("倒计时结束后自动暂停播放；也可以选择在当前歌曲结束后暂停。")
                }
            }
            .adaptiveListBackground()
            .navigationTitle("播放选项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 播放队列

struct PlayQueueView: View {
    @EnvironmentObject private var player: PlayerStore
    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, song in
                    Button {
                        Task {
                            await player.play(at: index)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            CoverImage(urlString: song.albumPicUrl, size: 40, cornerRadius: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(song.artistText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if index == player.currentIndex {
                                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                                    .foregroundStyle(Color.splayerAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(editMode == .active)
                    .listRowBackground(
                        index == player.currentIndex
                            ? Color.splayerAccent.opacity(0.08)
                            : Color.clear
                    )
                }
                .onMove { source, destination in
                    player.moveQueue(fromOffsets: source, toOffset: destination)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !player.queue.isEmpty {
                        Button(editMode == .active ? "完成" : "排序") {
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                            }
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}
