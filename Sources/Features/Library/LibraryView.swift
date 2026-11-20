import SwiftUI

/// 资料库：M2 接入登录，M3 实现歌单列表
struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "资料库",
                systemImage: "music.note.list",
                description: Text("登录后将展示你的歌单（M3 实现）")
            )
            .navigationTitle("资料库")
        }
    }
}
