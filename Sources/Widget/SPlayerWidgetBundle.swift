import SwiftUI
import WidgetKit

@main
struct SPlayerWidgetBundle: WidgetBundle {
    var body: some Widget {
        SPlayerLyricWidget()
        SPlayerLyricLiveActivity()
    }
}

// MARK: - 桌面歌词小组件

struct LyricEntry: TimelineEntry {
    let date: Date
    let item: SharedNowPlaying?
}

struct LyricProvider: TimelineProvider {
    func placeholder(in context: Context) -> LyricEntry {
        var sample = SharedNowPlaying()
        sample.songId = 1
        sample.title = "SPlayer"
        sample.artist = "网易云音乐"
        sample.lyricLine = "桌面歌词小组件"
        sample.lyricTranslation = "SPlayer-Next for iOS"
        sample.duration = 240
        sample.progress = 80
        return LyricEntry(date: Date(), item: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LyricEntry) -> Void) {
        completion(LyricEntry(date: Date(), item: SharedStore.load() ?? placeholder(in: context).item))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LyricEntry>) -> Void) {
        let entry = LyricEntry(date: Date(), item: SharedStore.load())
        let next = Date().addingTimeInterval(10 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SPlayerLyricWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: LyricProvider()) { entry in
            LyricWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.13, blue: 0.15),
                            Color(red: 0.07, green: 0.07, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("桌面歌词")
        .description("显示当前播放歌曲与歌词。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LyricWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LyricEntry

    private let accent = Color(red: 0.996, green: 0.475, blue: 0.443)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent)
                Text("SPlayer")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                Image(systemName: entry.item?.isPlaying == true ? "waveform" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer(minLength: 0)

            if let item = entry.item, !item.title.isEmpty {
                Text(item.lyricLine.isEmpty ? item.title : item.lyricLine)
                    .font(family == .systemSmall
                          ? .system(size: 15, weight: .semibold)
                          : .system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if let translation = item.lyricTranslation, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if family == .systemMedium {
                    Text("\(item.title) · \(item.artist)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                ProgressView(value: item.duration > 0 ? min(max(item.progress / item.duration, 0), 1) : 0)
                    .tint(accent)
            } else {
                Spacer(minLength: 0)
                Text("暂无播放")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text("在 SPlayer 中播放歌曲后，这里会显示歌词")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
        .padding(2)
        .widgetURL(URL(string: "splayer://player"))
    }
}

// MARK: - 灵动岛 / 锁屏歌词

struct SPlayerLyricLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LyricActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .foregroundStyle(Color(red: 0.996, green: 0.475, blue: 0.443))
                    Text(context.attributes.songTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(context.state.isPlaying ? "播放中" : "已暂停")
                        .font(.caption2)
                        .opacity(0.6)
                }

                Text(context.state.line.isEmpty ? context.attributes.songTitle : context.state.line)
                    .font(.headline)
                    .lineLimit(2)

                if let translation = context.state.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.caption)
                        .opacity(0.68)
                        .lineLimit(1)
                }

                HStack {
                    Text(context.attributes.artist)
                        .font(.caption2)
                        .opacity(0.55)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                ProgressView(value: context.state.progress)
                    .tint(Color(red: 0.996, green: 0.475, blue: 0.443))
            }
            .padding(14)
            .activityBackgroundTint(Color.black.opacity(0.55))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "music.note")
                        .foregroundStyle(Color(red: 0.996, green: 0.475, blue: 0.443))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.isPlaying ? "播放中" : "已暂停")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.line.isEmpty ? context.attributes.songTitle : context.state.line)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let translation = context.state.translation, !translation.isEmpty {
                            Text(translation)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text("\(context.attributes.songTitle) · \(context.attributes.artist)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "music.note")
                    .foregroundStyle(Color(red: 0.996, green: 0.475, blue: 0.443))
            } compactTrailing: {
                Text(context.state.line.isEmpty ? "SPlayer" : context.state.line)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "music.note")
                    .foregroundStyle(Color(red: 0.996, green: 0.475, blue: 0.443))
            }
        }
    }
}
