import SwiftUI
import UniformTypeIdentifiers

/// 我的云盘（仅展示可播放的云端歌曲）
struct CloudMusicView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var player: PlayerStore

    @State private var songs: [Song] = []
    @State private var isLoading = false
    @State private var loadedOnce = false
    @State private var errorText: String?
    @State private var showImporter = false
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var uploadSucceeded = false

    var body: some View {
        List {
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                SongRow(index: index + 1, song: song, showsLikeButton: true)
                    .foregroundStyle(player.currentSong?.id == song.id ? Color.splayerAccent : Color.primary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await player.play(song: song, in: songs) }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("删除", role: .destructive) {
                            Task { await delete(song) }
                        }
                    }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle("我的云盘")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isUploading {
                    ProgressView()
                } else {
                    Button {
                        showImporter = true
                    } label: {
                        Label("上传到云盘", systemImage: "arrow.up.circle")
                    }
                    .disabled(auth.cookie == nil)
                }
            }
            if !songs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await player.play(songs, startAt: 0) }
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await upload(url) }
            case .failure(let error):
                uploadError = error.localizedDescription
            }
        }
        .alert("上传成功", isPresented: $uploadSucceeded) {
            Button("好", role: .cancel) {}
        } message: {
            Text("歌曲已上传到云盘，正在刷新列表。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(uploadError ?? "")
        }
        .refreshable {
            await load()
        }
        .task {
            if !loadedOnce {
                await load()
            }
        }
        .overlay {
            if isLoading, songs.isEmpty {
                ProgressView()
            } else if let errorText, songs.isEmpty, !isLoading {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorText)
                } actions: {
                    Button("重试") {
                        Task { await load() }
                    }
                }
            } else if loadedOnce, songs.isEmpty, !isLoading {
                ContentUnavailableView(
                    "云盘暂无歌曲",
                    systemImage: "cloud",
                    description: Text("点击右上角上传音乐，或在网易云客户端上传后同步到这里")
                )
            }
        }
    }

    private func delete(_ song: Song) async {
        guard let cookie = auth.cookie else {
            uploadError = "请先登录"
            return
        }

        do {
            try await NeteaseAPI().deleteCloudSong(id: song.id, cookie: cookie)
            songs.removeAll { $0.id == song.id }
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func upload(_ url: URL) async {
        guard let cookie = auth.cookie else {
            uploadError = "请先登录"
            return
        }
        guard !isUploading else { return }
        isUploading = true
        defer { isUploading = false }

        do {
            try await NeteaseAPI().uploadCloudSong(fileURL: url, cookie: cookie)
            await load()
            uploadSucceeded = true
        } catch {
            uploadError = error.localizedDescription
        }
    }

    private func load() async {
        guard !isLoading else { return }
        guard let cookie = auth.cookie else {
            errorText = "请先登录"
            return
        }
        isLoading = true
        errorText = nil
        defer {
            isLoading = false
            loadedOnce = true
        }

        do {
            songs = try await NeteaseAPI().cloudSongs(cookie: cookie)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
