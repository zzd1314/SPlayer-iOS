import AVKit
import SwiftUI

/// MV 播放页：使用 AVPlayer 播放 /mv/url 返回的地址
struct MVPlayerView: View {
    let mv: MVSummary

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var avPlayer: AVPlayer?
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var showComments = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black

                if let avPlayer {
                    VideoPlayer(player: avPlayer)
                } else if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let errorText {
                    VStack(spacing: 10) {
                        Text("MV 加载失败")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("重试") {
                            Task { await load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)

            List {
                Section {
                    LabeledContent("名称", value: mv.name)
                    if let artist = mv.artistName, !artist.isEmpty {
                        LabeledContent("歌手", value: artist)
                    }
                    if let count = mv.playCount {
                        LabeledContent("播放", value: "\(count)")
                    }
                }
            }
            .listStyle(.plain)
            .adaptiveListBackground()
        }
        .navigationTitle(mv.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showComments = true
                } label: {
                    Label("评论", systemImage: "bubble.left")
                }
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsView(resource: .mv(mv.id), title: mv.name)
        }
        .task {
            if avPlayer == nil {
                await load()
            }
        }
        .onDisappear {
            avPlayer?.pause()
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            guard let url = try await NeteaseAPI().mvURL(id: mv.id, cookie: auth.cookie) else {
                errorText = "当前 MV 暂无可用播放地址"
                return
            }

            // 避免 MV 与音乐同时出声
            if player.isPlaying {
                player.togglePlayPause()
            }

            let item = AVPlayer(url: url)
            avPlayer = item
            item.play()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
