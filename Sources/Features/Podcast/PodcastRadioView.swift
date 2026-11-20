import SwiftUI

/// 电台详情与节目列表
struct PodcastRadioView: View {
    let radio: PodcastRadio

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var detail: PodcastRadio?
    @State private var programs: [PodcastProgram] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var canLoadMore = false
    @State private var errorMessage: String?

    private let pageSize = 30

    private var info: PodcastRadio {
        detail ?? radio
    }

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if isLoading, programs.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载节目…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            } else if let errorMessage, programs.isEmpty {
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
                    .padding(.vertical, 6)
                }
            } else if !programs.isEmpty {
                Section {
                    ForEach(programs) { program in
                        NavigationLink {
                            PodcastProgramDetailView(program: program)
                        } label: {
                            PodcastProgramRow(program: program)
                        }
                    }

                    if canLoadMore {
                        Button {
                            Task { await loadMore() }
                        } label: {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView()
                                } else {
                                    Text("加载更多")
                                        .font(.footnote)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isLoadingMore)
                    }
                } header: {
                    Text("节目")
                }
            }
        }
        .adaptiveListBackground()
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    playAll()
                } label: {
                    Label("播放全部", systemImage: "play.fill")
                }
                .disabled(programs.compactMap(\.mainSong).isEmpty)
            }
        }
        .task {
            await load()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            CoverImage(urlString: info.picUrl, size: 160, cornerRadius: 16)

            Text(info.name)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            if let dj = info.dj?.nickname, !dj.isEmpty {
                Text(dj)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let count = info.programCount, count > 0 {
                    Label("\(count) 期", systemImage: "waveform")
                }
                if let subs = info.subCount, subs > 0 {
                    Label("\(PodcastFormat.listeners(subs))订阅", systemImage: "person.2")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            if let description = info.desc, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(6)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func playAll() {
        let songs = programs.compactMap(\.mainSong)
        guard !songs.isEmpty else { return }
        Task { await player.play(songs, startAt: 0) }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let api = NeteaseAPI()
        let cookie = auth.cookie

        if let fetched = try? await api.podcastRadioDetail(id: radio.id, cookie: cookie) {
            detail = fetched
        }

        do {
            let result = try await api.radioPrograms(
                radioId: radio.id,
                limit: pageSize,
                offset: 0,
                cookie: cookie
            )
            programs = result
            canLoadMore = result.count >= pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await NeteaseAPI().radioPrograms(
                radioId: radio.id,
                limit: pageSize,
                offset: programs.count,
                cookie: auth.cookie
            )
            programs.append(contentsOf: result)
            canLoadMore = result.count >= pageSize
        } catch {
            canLoadMore = false
        }
    }
}
