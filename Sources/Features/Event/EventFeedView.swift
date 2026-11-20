import SwiftUI

/// 云村动态：关注动态流，支持点赞与播放分享歌曲
struct EventFeedView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var events: [EventItem] = []
    @State private var lasttime: Int?
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var loadedOnce = false
    @State private var errorText: String?
    @State private var actionError: String?

    var body: some View {
        List {
            ForEach(events) { event in
                EventCard(
                    event: event,
                    onLike: { Task { await toggleLike(event) } },
                    onPlaySong: { song in Task { await player.play(song: song, in: [song]) } }
                )
                .listRowSeparator(.hidden)
                .onAppear {
                    if event.id == events.last?.id {
                        Task { await loadMore() }
                    }
                }
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle("云村动态")
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
            if isLoading, events.isEmpty {
                ProgressView()
            } else if let errorText, events.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
            } else if loadedOnce, events.isEmpty, !isLoading {
                ContentUnavailableView(
                    "暂无动态",
                    systemImage: "text.bubble",
                    description: Text("关注更多用户后，他们的动态会出现在这里")
                )
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func load() async {
        guard !isLoading else { return }
        guard let cookie = auth.cookie else {
            errorText = "请先登录后查看动态"
            return
        }

        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            let result = try await NeteaseAPI().events(cookie: cookie)
            events = result.events
            lasttime = result.lasttime
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, !isLoading else { return }
        guard let cookie = auth.cookie, let lasttime, lasttime > 0 else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await NeteaseAPI().events(lasttime: lasttime, cookie: cookie)
            let existing = Set(events.map(\.id))
            let fresh = result.events.filter { !existing.contains($0.id) }

            if fresh.isEmpty || result.lasttime == lasttime {
                self.lasttime = nil
            } else {
                events.append(contentsOf: fresh)
                self.lasttime = result.lasttime
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func toggleLike(_ event: EventItem) async {
        guard let cookie = auth.cookie,
              let index = events.firstIndex(where: { $0.id == event.id }),
              event.id > 0
        else { return }

        let target = !(events[index].info?.liked ?? false)
        do {
            try await NeteaseAPI().likeEvent(id: event.id, like: target, cookie: cookie)
            events[index].info?.liked = target
            let count = events[index].info?.likedCount ?? 0
            events[index].info?.likedCount = max(0, count + (target ? 1 : -1))
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// 单条动态卡片
private struct EventCard: View {
    let event: EventItem
    let onLike: () -> Void
    let onPlaySong: (Song) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(event.nickname)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let time = event.time {
                        Text(timeText(time))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = event.message, !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let pics = event.pics, !pics.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(pics.prefix(3), id: \.self) { pic in
                            AsyncImage(url: URL(string: pic)) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    Color(.tertiarySystemFill)
                                }
                            }
                            .frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }

                if let song = event.sharedSong {
                    Button {
                        onPlaySong(song)
                    } label: {
                        HStack(spacing: 10) {
                            CoverImage(urlString: song.albumPicUrl, size: 42, cornerRadius: 6)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(song.artistText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.splayerAccent)
                        }
                        .padding(8)
                        .background(
                            Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 18) {
                    Button {
                        onLike()
                    } label: {
                        Label(
                            "\(event.info?.likedCount ?? 0)",
                            systemImage: (event.info?.liked ?? false) ? "heart.fill" : "heart"
                        )
                        .foregroundStyle((event.info?.liked ?? false) ? Color.splayerAccent : Color.secondary)
                    }

                    Label("\(event.info?.commentCount ?? 0)", systemImage: "bubble.left")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = event.avatarURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholderAvatar
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            placeholderAvatar
                .frame(width: 38, height: 38)
        }
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemFill))
            Image(systemName: "person.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timeText(_ milliseconds: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        let interval = -date.timeIntervalSinceNow

        if interval < 60 {
            return "刚刚"
        }
        if interval < 3600 {
            return "\(Int(interval / 60)) 分钟前"
        }
        if interval < 86400 {
            return "\(Int(interval / 3600)) 小时前"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}
