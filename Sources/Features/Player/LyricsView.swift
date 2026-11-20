import SwiftUI

/// 逐行歌词（AMLL 风格）：当前行高亮 + 翻译 + 跟随封面颜色
struct LyricsView: View {
    @EnvironmentObject private var player: PlayerStore

    @AppStorage("showTranslation") private var showTranslation = true
    @AppStorage("showRomanization") private var showRomanization = false
    @AppStorage("lyricFontSize") private var lyricFontSize = 22.0
    @AppStorage("lyricAlignment") private var lyricAlignment = "auto"
    @AppStorage("inactiveAlpha") private var inactiveAlpha = 0.45
    @AppStorage("followCoverColor") private var followCoverColor = true

    private var accent: Color {
        followCoverColor ? (player.coverAccent ?? .splayerAccent) : .splayerAccent
    }

    private var textAlignment: TextAlignment {
        switch lyricAlignment {
        case "left": return .leading
        case "right": return .trailing
        default: return .center
        }
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch lyricAlignment {
        case "left": return .leading
        case "right": return .trailing
        default: return .center
        }
    }

    private var frameAlignment: Alignment {
        switch lyricAlignment {
        case "left": return .leading
        case "right": return .trailing
        default: return .center
        }
    }

    var body: some View {
        Group {
            if player.isLoadingLyrics && player.lyricLines.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if player.lyricLines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.title2)
                    Text(player.lyricError ?? "暂无歌词")
                        .font(.subheadline)
                }
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: horizontalAlignment, spacing: 18) {
                            ForEach(player.lyricLines) { line in
                                lyricRow(line)
                                    .id(line.id)
                                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                                    .onTapGesture {
                                        player.seek(to: line.time)
                                    }
                            }
                        }
                        .padding(.vertical, 90)
                        .padding(.horizontal, 4)
                    }
                    .onAppear {
                        if let index = player.currentLyricIndex {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                    .onChange(of: player.currentLyricIndex) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func lyricRow(_ line: LyricLine) -> some View {
        let index = player.currentLyricIndex
        let isCurrent = index == line.id
        let isPassed = index.map { line.id < $0 } ?? false
        let baseAlpha = isPassed ? max(inactiveAlpha - 0.18, 0.12) : inactiveAlpha

        return VStack(alignment: horizontalAlignment, spacing: 4) {
            if isCurrent, let words = line.words, !words.isEmpty {
                karaokeText(words)
                    .multilineTextAlignment(textAlignment)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            } else {
                Text(line.text)
                    .font(
                        .system(
                            size: isCurrent ? lyricFontSize * 1.1 : lyricFontSize,
                            weight: isCurrent ? .semibold : .regular
                        )
                    )
                    .foregroundStyle(isCurrent ? accent : Color.white.opacity(baseAlpha))
                    .multilineTextAlignment(textAlignment)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .shadow(color: .black.opacity(isCurrent ? 0.18 : 0), radius: 6, y: 2)
            }

            if showRomanization, let romanization = line.romanization, !romanization.isEmpty {
                Text(romanization)
                    .font(.system(size: lyricFontSize * 0.58, weight: .regular))
                    .foregroundStyle(.white.opacity(isCurrent ? 0.6 : baseAlpha * 0.7))
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showTranslation, let translation = line.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: lyricFontSize * 0.62, weight: .regular))
                    .foregroundStyle(.white.opacity(isCurrent ? 0.68 : baseAlpha * 0.75))
                    .multilineTextAlignment(textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isCurrent)
    }

    /// 逐字歌词：已唱部分使用主题色，未唱部分半透明
    private func karaokeText(_ words: [LyricWord]) -> Text {
        let now = player.currentTime + AppSettings.lyricOffset
        let text = words.reduce(Text("")) { partial, word in
            let sung = now >= word.time
            return partial + Text(word.text)
                .foregroundColor(sung ? accent : Color.white.opacity(0.5))
        }
        return text.font(.system(size: lyricFontSize * 1.1, weight: .semibold))
    }
}
