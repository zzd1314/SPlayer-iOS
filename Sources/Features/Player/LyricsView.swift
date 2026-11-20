import SwiftUI

/// 歌词视图：按播放进度高亮并自动滚动
struct LyricsView: View {
    let song: Song

    @EnvironmentObject private var player: PlayerStore

    @State private var lines: [LyricLine] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private var currentIndex: Int? {
        guard !lines.isEmpty else { return nil }
        let time = player.currentTime
        var index: Int?
        for (i, line) in lines.enumerated() where line.time <= time + 0.2 {
            index = i
        }
        return index
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else if lines.isEmpty {
                Text("暂无歌词")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 14) {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(line.id == currentIndex ? .headline : .subheadline)
                                    .foregroundStyle(style(for: line))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .id(line.id)
                            }
                        }
                        .padding(.vertical, 60)
                    }
                    .onChange(of: currentIndex) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(height: 300)
        .task(id: song.id) {
            await load()
        }
    }

    private func style(for line: LyricLine) -> Color {
        if line.id == currentIndex {
            return .splayerAccent
        }
        if let currentIndex, line.id < currentIndex {
            return Color.secondary.opacity(0.5)
        }
        return Color.primary.opacity(0.85)
    }

    private func load() async {
        isLoading = true
        errorText = nil
        lines = []

        do {
            lines = try await NeteaseAPI().lyric(id: song.id, cookie: player.cookie)
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
