import SwiftUI

/// 播客节目详情
struct PodcastProgramDetailView: View {
    let program: PodcastProgram

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var detail: PodcastProgram?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var info: PodcastProgram {
        detail ?? program
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载节目详情…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let description = info.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("节目介绍")
                            .font(.headline)
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("节目详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            CoverImage(
                urlString: info.coverUrl ?? info.radio?.picUrl,
                size: 200,
                cornerRadius: 16
            )

            Text(info.name)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if let dj = info.dj?.nickname, !dj.isEmpty {
                Text(dj)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let radioName = info.radio?.name, !radioName.isEmpty {
                Text(radioName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Label(PodcastFormat.duration(info.duration), systemImage: "clock")
                if let listeners = info.listenerCount, listeners > 0 {
                    Label("\(PodcastFormat.listeners(listeners))播放", systemImage: "headphones")
                }
                if let dateText {
                    Label(dateText, systemImage: "calendar")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Button {
                play()
            } label: {
                Label("播放节目", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(Color.splayerAccent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(info.mainSong == nil)
            .opacity(info.mainSong == nil ? 0.5 : 1)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var dateText: String? {
        guard let milliseconds = info.createTime, milliseconds > 0 else { return nil }
        let date = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func play() {
        guard let song = info.mainSong else { return }
        Task { await player.play([song], startAt: 0) }
    }

    private func load() async {
        guard !isLoading, detail == nil else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            detail = try await NeteaseAPI().podcastProgramDetail(
                id: program.id,
                cookie: auth.cookie
            )
            errorMessage = nil
        } catch {
            errorMessage = "节目详情加载失败：\(error.localizedDescription)"
        }
    }
}
