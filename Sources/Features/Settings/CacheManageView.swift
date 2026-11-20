import SwiftUI

/// 缓存管理：查看 / 播放 / 删除已缓存的歌曲
struct CacheManageView: View {
    @EnvironmentObject private var player: PlayerStore

    @State private var entries: [AudioCache.Entry] = []
    @State private var songs: [Int: Song] = [:]
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var showClearConfirm = false

    private var totalSize: Int64 {
        entries.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("已缓存歌曲", value: "\(entries.count) 首")
                LabeledContent("占用空间", value: sizeText(totalSize))
            }

            Section {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在读取缓存信息…")
                            .foregroundStyle(.secondary)
                    }
                } else if entries.isEmpty {
                    Text("暂无缓存歌曲")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        row(for: entry)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("删除", role: .destructive) {
                                    delete(entry)
                                }
                            }
                    }
                }
            } header: {
                Text("已缓存歌曲")
            } footer: {
                if let loadError {
                    Text("部分歌曲信息加载失败：\(loadError)")
                } else {
                    Text("点击歌曲直接播放，左滑可删除单曲缓存。")
                }
            }

            Section {
                Button("清除全部缓存", role: .destructive) {
                    showClearConfirm = true
                }
                .disabled(entries.isEmpty)
            }
        }
        .adaptiveListBackground()
        .navigationTitle("缓存管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .confirmationDialog("清除全部歌曲缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                AudioCache.clear()
                entries = []
                songs = [:]
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("下次播放时会重新下载，操作不可恢复。")
        }
    }

    private func row(for entry: AudioCache.Entry) -> some View {
        let song = songs[entry.songId]
        let isCurrent = player.currentSong?.id == entry.songId
        return Button {
            play(entry)
        } label: {
            HStack(spacing: 10) {
                CoverImage(urlString: song?.albumPicUrl, size: 42, cornerRadius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(song?.name ?? "歌曲 \(entry.songId)")
                        .foregroundStyle(isCurrent ? Color.splayerAccent : .primary)
                        .lineLimit(1)
                    Text(song?.artistText ?? "缓存文件")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(sizeText(entry.size))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                if isCurrent {
                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                        .font(.caption)
                        .foregroundStyle(Color.splayerAccent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(song == nil)
    }

    private func load() async {
        entries = AudioCache.entries()
        isLoading = true
        defer { isLoading = false }

        let ids = entries.map(\.songId)
        guard !ids.isEmpty else {
            songs = [:]
            return
        }

        do {
            let list = try await NeteaseAPI().songDetails(ids: ids, cookie: nil)
            songs = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func play(_ entry: AudioCache.Entry) {
        let playable = entries.compactMap { songs[$0.songId] }
        guard let index = playable.firstIndex(where: { $0.id == entry.songId }) else { return }
        Task { await player.play(playable, startAt: index) }
    }

    private func delete(_ entry: AudioCache.Entry) {
        AudioCache.remove(songId: entry.songId)
        entries = AudioCache.entries()
    }

    private func sizeText(_ bytes: Int64) -> String {
        bytes == 0 ? "0 MB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
