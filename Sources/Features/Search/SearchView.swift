import SwiftUI

/// 搜索：M3 实现歌曲搜索（/cloudsearch）
struct SearchView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "搜索",
                systemImage: "magnifyingglass",
                description: Text("歌曲搜索将在 M3 实现")
            )
            .navigationTitle("搜索")
        }
    }
}
