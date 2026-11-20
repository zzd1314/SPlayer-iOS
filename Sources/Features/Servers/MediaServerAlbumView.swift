import SwiftUI

/// 媒体服务器专辑详情
struct MediaServerAlbumView: View {
    let server: MediaServer
    let album: MediaServerAlbum

    @EnvironmentObject private var player: PlayerStore

    @State private var tracks: [MediaServerTrack] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if isLoading && tracks.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载歌曲…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let errorMessage, tracks.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("重试") {
                            Task { await load() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            } else if !tracks.isEmpty {
                Section {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                        Button {
                            play(at: index)
                        } label: {
                            row(for: track, index: index)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(tracks.count) 首")
                }
            }
        }
        .adaptiveListBackground()
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            CoverImage(urlString: album.coverURL?.absoluteString, size: 180, cornerRadius: 14)

            Text(album.name)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if let artist = album.artist, !artist.isEmpty {
                Text(artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let year = album.year {
                Text(String(year))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Button {
                playAll()
            } label: {
                Label("播放全部", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.splayerAccent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)
            .opacity(tracks.isEmpty ? 0.5 : 1)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func row(for track: MediaServerTrack, index: Int) -> some View {
        let current = isCurrent(track)
        return HStack(spacing: 10) {
            Text(track.trackNumber.map(String.init) ?? "\(index + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .foregroundStyle(current ? Color.splayerAccent : .primary)
                    .lineLimit(1)
                if let artist = track.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            Text(durationText(track.duration))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            if current {
                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                    .font(.caption)
                    .foregroundStyle(Color.splayerAccent)
            }
        }
        .padding(.vertical, 2)
    }

    private func isCurrent(_ track: MediaServerTrack) -> Bool {
        guard let song = player.currentSong else { return false }
        return song.id < 0 && song.name == track.title
    }

    private func playAll() {
        guard !tracks.isEmpty else { return }
        let songs = tracks.map { $0.song(server: server, album: album) }
        Task { await player.play(songs, startAt: 0) }
    }

    private func play(at index: Int) {
        let songs = tracks.map { $0.song(server: server, album: album) }
        guard songs.indices.contains(index) else { return }
        Task { await player.play(songs, startAt: index) }
    }

    private func load() async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        do {
            tracks = try await MediaServerClient.tracks(server: server, album: album)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func durationText(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
