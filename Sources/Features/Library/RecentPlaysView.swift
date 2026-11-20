import SwiftUI

/// 最近播放：读取 PlayerStore 的本地记录
struct RecentPlaysView: View {
    @EnvironmentObject private var player: PlayerStore

    @State private var showClearConfirm = false

    var body: some View {
        List {
            Section {
                ForEach(Array(player.recentSongs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        Task { await player.play(song: song, in: player.recentSongs) }
                    } label: {
                        SongRow(index: index + 1, song: song)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                }

                if player.recentSongs.isEmpty {
                    Text("还没有播放记录")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            } header: {
                if !player.recentSongs.isEmpty {
                    Text("\(player.recentSongs.count) 首歌曲")
                }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle("最近播放")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !player.recentSongs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await player.play(player.recentSongs, startAt: 0) }
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) {
                        showClearConfirm = true
                    }
                }
            }
        }
        .confirmationDialog("清空最近播放？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                player.clearRecent()
            }
        } message: {
            Text("只会清除本机的播放记录，不影响账号数据。")
        }
    }
}
