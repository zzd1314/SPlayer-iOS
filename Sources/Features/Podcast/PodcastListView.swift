import SwiftUI

/// 播客电台首页：热门电台 + 推荐节目
struct PodcastListView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var radios: [PodcastRadio] = []
    @State private var programs: [PodcastProgram] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !radios.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(radios) { radio in
                                NavigationLink {
                                    PodcastRadioView(radio: radio)
                                } label: {
                                    PodcastRadioCard(radio: radio)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                } header: {
                    Text("热门电台")
                }
            }

            if !programs.isEmpty {
                Section {
                    ForEach(programs) { program in
                        NavigationLink {
                            PodcastProgramDetailView(program: program)
                        } label: {
                            PodcastProgramRow(program: program)
                        }
                    }
                } header: {
                    Text("推荐节目")
                }
            }

            if isLoading, radios.isEmpty, programs.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载播客…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
            }

            if let errorMessage, radios.isEmpty, programs.isEmpty, !isLoading {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("重试") {
                            Task { await load(force: true) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .adaptiveListBackground()
        .navigationTitle("播客电台")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load(force: true)
        }
        .task {
            if !loadedOnce {
                await load(force: true)
            }
        }
    }

    private func load(force: Bool) async {
        guard !isLoading else { return }
        if loadedOnce && !force { return }

        isLoading = true
        errorMessage = nil

        let api = NeteaseAPI()
        let cookie = auth.cookie
        async let radiosTask = api.hotPodcastRadios(cookie: cookie)
        async let programsTask = api.recommendedPodcastPrograms(cookie: cookie)

        let fetchedRadios = (try? await radiosTask) ?? []
        let fetchedPrograms = (try? await programsTask) ?? []

        radios = fetchedRadios
        programs = fetchedPrograms
        isLoading = false
        loadedOnce = true

        if fetchedRadios.isEmpty && fetchedPrograms.isEmpty {
            errorMessage = "暂时无法获取播客内容，请稍后重试"
        }
    }
}

// MARK: - 共用组件

struct PodcastRadioCard: View {
    let radio: PodcastRadio

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(urlString: radio.picUrl, size: 130, cornerRadius: 12)

            Text(radio.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 130, alignment: .leading)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let dj = radio.dj?.nickname, !dj.isEmpty {
            parts.append(dj)
        }
        if let count = radio.programCount, count > 0 {
            parts.append("\(count) 期")
        }
        return parts.isEmpty ? "电台" : parts.joined(separator: " · ")
    }
}

struct PodcastProgramRow: View {
    let program: PodcastProgram

    var body: some View {
        HStack(spacing: 10) {
            CoverImage(
                urlString: program.coverUrl ?? program.radio?.picUrl,
                size: 52,
                cornerRadius: 8
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(program.name)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(meta)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var meta: String {
        var parts: [String] = []
        if let name = program.dj?.nickname ?? program.radio?.name, !name.isEmpty {
            parts.append(name)
        }
        parts.append(PodcastFormat.duration(program.duration))
        if let listeners = program.listenerCount, listeners > 0 {
            parts.append("\(PodcastFormat.listeners(listeners))播放")
        }
        return parts.joined(separator: " · ")
    }
}

enum PodcastFormat {
    static func duration(_ milliseconds: Int) -> String {
        let total = max(0, milliseconds / 1000)
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func listeners(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f万", Double(count) / 10_000)
        }
        return "\(count)"
    }
}
