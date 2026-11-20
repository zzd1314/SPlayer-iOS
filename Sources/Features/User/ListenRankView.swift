import SwiftUI

/// 听歌排行：最近一周 / 全部时间
struct ListenRankView: View {
    let userId: Int

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var type = 1
    @State private var records: [PlayRecord] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    private var songs: [Song] {
        records.compactMap(\.song)
    }

    var body: some View {
        List {
            Picker("排行范围", selection: $type) {
                Text("最近一周").tag(1)
                Text("全部时间").tag(0)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)
            .onChange(of: type) { _, _ in
                Task { await load() }
            }

            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                if let song = record.song {
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(index < 3 ? Color.splayerAccent : Color.secondary)
                            .frame(width: 22, alignment: .trailing)

                        SongRow(
                            index: nil,
                            song: song,
                            showsLikeButton: true
                        )
                        .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await player.play(song: song, in: songs) }
                        }

                        if let count = record.playCount {
                            Text("\(count) 次")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle("听歌排行")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load()
        }
        .task {
            if !loadedOnce {
                await load()
            }
        }
        .overlay {
            if isLoading, records.isEmpty {
                ProgressView()
            } else if let errorText, records.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
            } else if loadedOnce, records.isEmpty, !isLoading {
                ContentUnavailableView(
                    "暂无听歌记录",
                    systemImage: "chart.bar",
                    description: Text("多听几首歌再来看看吧")
                )
            }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            records = try await NeteaseAPI().userRecords(
                uid: userId,
                type: type,
                cookie: auth.cookie
            )
        } catch {
            records = []
            errorText = error.localizedDescription
        }
    }
}
