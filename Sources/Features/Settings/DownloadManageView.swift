import SwiftUI

/// 下载管理：查看 / 播放 / 删除已下载歌曲
struct DownloadManageView: View {
    @EnvironmentObject private var player: PlayerStore

    @State private var items: [DownloadStore.Item] = []
    @State private var showClearConfirm = false

    private var totalSize: Int64 {
        items.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("已下载歌曲", value: "\(items.count) 首")
                LabeledContent("占用空间", value: sizeText(totalSize))
            }

            Section {
                if items.isEmpty {
                    Text("暂无下载歌曲")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        row(for: item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("删除", role: .destructive) {
                                    delete(item)
                                }
                            }
                    }
                }
            } header: {
                Text("已下载歌曲")
            } footer: {
                Text("点击歌曲直接播放，左滑可删除单曲下载。")
            }

            Section {
                Button("清除全部下载", role: .destructive) {
                    showClearConfirm = true
                }
                .disabled(items.isEmpty)
            }
        }
        .adaptiveListBackground()
        .navigationTitle("下载管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            items = DownloadStore.items()
        }
        .confirmationDialog("清除全部下载？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                DownloadStore.clear()
                items = []
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("下载的歌曲文件将被删除，操作不可恢复。")
        }
    }

    private func row(for item: DownloadStore.Item) -> some View {
        let isCurrent = player.currentSong?.id == item.song.id
        return Button {
            play(item)
        } label: {
            HStack(spacing: 10) {
                CoverImage(urlString: item.song.albumPicUrl, size: 42, cornerRadius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.song.name)
                        .foregroundStyle(isCurrent ? Color.splayerAccent : .primary)
                        .lineLimit(1)

                    Text(item.song.artistText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(item.qualityLabel) · \(sizeText(item.size))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 6)

                if isCurrent {
                    Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                        .font(.caption)
                        .foregroundStyle(Color.splayerAccent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func play(_ item: DownloadStore.Item) {
        guard let index = items.firstIndex(where: { $0.song.id == item.song.id }) else { return }
        Task { await player.play(items.map(\.song), startAt: index) }
    }

    private func delete(_ item: DownloadStore.Item) {
        DownloadStore.remove(item.song.id)
        items = DownloadStore.items()
    }

    private func sizeText(_ bytes: Int64) -> String {
        bytes == 0 ? "0 MB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
