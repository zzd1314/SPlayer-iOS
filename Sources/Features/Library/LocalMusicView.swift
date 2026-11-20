import SwiftUI
import UniformTypeIdentifiers

/// 本地音乐：导入音频文件、播放与删除
struct LocalMusicView: View {
    @EnvironmentObject private var player: PlayerStore

    @State private var tracks: [LocalMusicStore.Track] = []
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button {
                    showImporter = true
                } label: {
                    HStack {
                        Label(isImporting ? "正在导入…" : "导入本地歌曲", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isImporting)
            } footer: {
                Text("支持系统可解码的音频格式（mp3 / m4a / flac / wav 等）；导入后会拷贝到 App 文档目录。")
            }

            if !tracks.isEmpty {
                Section {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        row(for: track, index: index)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("删除", role: .destructive) {
                                    delete(track)
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("\(tracks.count) 首")
                        Spacer()
                        Button("播放全部") {
                            playAll()
                        }
                        .font(.caption)
                        .textCase(nil)
                    }
                }
            }
        }
        .adaptiveListBackground()
        .navigationTitle("本地音乐")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if tracks.isEmpty && !isImporting {
                ContentUnavailableView {
                    Label("暂无本地歌曲", systemImage: "folder")
                } description: {
                    Text("点击右上角或列表顶部按钮导入音频文件")
                } actions: {
                    Button("导入歌曲") {
                        showImporter = true
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showImporter = true
                } label: {
                    Label("导入", systemImage: "plus")
                }
                .disabled(isImporting)
            }
        }
        .onAppear {
            tracks = LocalMusicStore.allTracks()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                message = "导入失败：\(error.localizedDescription)"
            }
        }
        .alert("提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func row(for track: LocalMusicStore.Track, index: Int) -> some View {
        let isCurrent = player.currentSong?.id == track.song.id
        return Button {
            play(at: index)
        } label: {
            HStack(spacing: 10) {
                CoverImage(urlString: track.song.albumPicUrl, size: 44, cornerRadius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.song.name)
                        .foregroundStyle(isCurrent ? Color.splayerAccent : .primary)
                        .lineLimit(1)
                    Text(track.song.artistText.isEmpty ? "未知歌手" : track.song.artistText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(durationText(track.song.duration))
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
    }

    private func play(at index: Int) {
        let songs = tracks.map(\.song)
        Task { await player.play(songs, startAt: index) }
    }

    private func playAll() {
        guard !tracks.isEmpty else { return }
        Task { await player.play(tracks.map(\.song), startAt: 0) }
    }

    private func delete(_ track: LocalMusicStore.Track) {
        LocalMusicStore.delete(track)
        tracks = LocalMusicStore.allTracks()
    }

    private func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            isImporting = true
            let outcome = await LocalMusicStore.importFiles(urls)
            tracks = LocalMusicStore.allTracks()
            isImporting = false
            if outcome.failed > 0 {
                message = "成功导入 \(outcome.added) 首，\(outcome.failed) 个文件导入失败。"
            }
        }
    }

    private func durationText(_ milliseconds: Int) -> String {
        let total = max(0, milliseconds / 1000)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
