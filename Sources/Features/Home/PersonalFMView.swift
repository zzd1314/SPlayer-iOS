import SwiftUI

/// 私人 FM：按口味连续推荐，支持喜欢 / 不喜欢 / 换一批
struct PersonalFMView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                ContentUnavailableView(
                    "未登录",
                    systemImage: "radio",
                    description: Text("登录后即可收听私人 FM")
                )
            } else {
                content
            }
        }
        .navigationTitle("私人 FM")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !loadedOnce, auth.isLoggedIn {
                await load()
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 18) {
                CoverImage(
                    urlString: player.currentSong?.albumPicUrl,
                    size: 240,
                    cornerRadius: 18
                )
                .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
                .padding(.top, 12)

                VStack(spacing: 5) {
                    Text(player.currentSong?.name ?? "私人 FM")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(player.currentSong?.artistText ?? "根据你的口味推荐")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 34) {
                    Button {
                        Task { await dislike() }
                    } label: {
                        Image(systemName: "hand.thumbsdown")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .accessibilityLabel("不感兴趣")

                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 58))
                    }
                    .disabled(player.currentSong == nil)
                    .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

                    Button {
                        Task { await likeCurrent() }
                    } label: {
                        Image(systemName: player.isCurrentSongLiked ? "heart.fill" : "heart")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(player.isCurrentSongLiked ? Color.splayerAccent : Color.primary)
                    }
                    .accessibilityLabel(player.isCurrentSongLiked ? "取消喜欢" : "喜欢")
                }
                .buttonStyle(.plain)

                Button {
                    Task { await load() }
                } label: {
                    Label("换一批", systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.splayerAccent)
                .disabled(isLoading)

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
        .overlay {
            if isLoading, player.currentSong == nil {
                ProgressView("正在为你推荐…")
            }
        }
    }

    private func load() async {
        guard !isLoading, let cookie = auth.cookie else { return }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        // 单次只返回约 3 首，连续取三批拼成一组队列
        var songs: [Song] = []
        var seen = Set<Int>()
        do {
            for _ in 0..<3 {
                let batch = try await NeteaseAPI().personalFM(cookie: cookie)
                for song in batch where !seen.contains(song.id) {
                    seen.insert(song.id)
                    songs.append(song)
                }
            }
        } catch {
            errorText = error.localizedDescription
        }

        guard !songs.isEmpty else {
            if errorText == nil {
                errorText = "暂时没有新的推荐，请稍后再试"
            }
            return
        }
        await player.play(songs, startAt: 0)
    }

    private func dislike() async {
        guard player.currentSong != nil else { return }
        if player.currentIndex + 1 >= player.queue.count {
            await load()
        } else {
            await player.next()
        }
    }

    private func likeCurrent() async {
        guard let song = player.currentSong else { return }
        do {
            try await player.toggleLike(songId: song.id)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
