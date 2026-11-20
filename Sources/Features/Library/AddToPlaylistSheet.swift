import SwiftUI

/// 将自己的歌单列为可选项，把歌曲加入所选歌单
struct AddToPlaylistSheet: View {
    let song: Song

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var addingId: Int?
    @State private var addedIds: Set<Int> = []

    var body: some View {
        NavigationStack {
            List(playlists) { playlist in
                Button {
                    Task { await add(playlist) }
                } label: {
                    HStack(spacing: 10) {
                        CoverImage(urlString: playlist.coverImgUrl, size: 44, cornerRadius: 6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(playlist.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Text("\(playlist.trackCount ?? 0) 首")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 4)

                        if addingId == playlist.id {
                            ProgressView()
                        } else if addedIds.contains(playlist.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.splayerAccent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(addingId != nil || addedIds.contains(playlist.id))
            }
            .listStyle(.plain)
            .navigationTitle("添加到歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isLoading, playlists.isEmpty {
                    ProgressView()
                }
            }
            .overlay {
                if let loadError, playlists.isEmpty, !isLoading {
                    ContentUnavailableView {
                        Label("加载失败", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("重试") {
                            Task { await load() }
                        }
                    }
                }
            }
            .task {
                if playlists.isEmpty {
                    await load()
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
    }

    private func load() async {
        guard !isLoading else { return }
        guard let uid = auth.profile?.userId else {
            loadError = "请先登录"
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let all = try await NeteaseAPI().userPlaylists(uid: uid, cookie: auth.cookie)
            // 「我喜欢的音乐」为特殊歌单，不支持通过 /playlist/tracks 添加
            playlists = all.filter { $0.name != "我喜欢的音乐" }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func add(_ playlist: Playlist) async {
        guard let cookie = auth.cookie else { return }
        addingId = playlist.id
        defer { addingId = nil }

        do {
            try await NeteaseAPI().modifyPlaylistTracks(
                playlistId: playlist.id,
                op: "add",
                trackIds: [song.id],
                cookie: cookie
            )
            addedIds.insert(playlist.id)
        } catch {
            actionError = error.localizedDescription
        }
    }
}
