import SwiftUI

/// 发现：桌面版侧栏「发现」入口，聚合排行榜 / 歌单广场 / 新歌 / 新碟 / 播客等
struct DiscoverView: View {
    @EnvironmentObject private var router: ShellRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? 230 : 160), spacing: 14)]
    }

    var body: some View {
        NavigationStack(path: router.binding(for: .discover)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("发现")
                            .font(.system(size: 28, weight: .bold))
                        Text("排行榜、新歌新碟、播客与云村动态")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        card(title: "排行榜", subtitle: "热门榜单实时更新", icon: "chart.bar.fill", tint: .orange) {
                            RankListView()
                        }
                        card(title: "歌单广场", subtitle: "按分类浏览精选歌单", icon: "square.grid.2x2.fill", tint: .blue) {
                            PlaylistSquareView()
                        }
                        card(title: "新歌速递", subtitle: "每天发现新发行", icon: "music.note.list", tint: .green) {
                            NewSongsView()
                        }
                        card(title: "新碟上架", subtitle: "最新专辑与单曲", icon: "opticaldisc.fill", tint: .purple) {
                            NewAlbumsView()
                        }
                        card(title: "播客电台", subtitle: "热门电台与节目", icon: "radio", tint: .pink) {
                            PodcastListView()
                        }
                        card(title: "全部歌手", subtitle: "按分类浏览歌手", icon: "person.2.fill", tint: .indigo) {
                            ArtistListView()
                        }
                        card(title: "云村动态", subtitle: "关注的人都在听什么", icon: "text.bubble.fill", tint: .teal) {
                            EventFeedView()
                        }
                        card(title: "私人 FM", subtitle: "根据口味不间断推荐", icon: "dot.radiowaves.left.and.right", tint: .splayerAccent) {
                            PersonalFMView()
                        }
                    }
                }
                .padding(.horizontal, horizontalSizeClass == .regular ? 28 : 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func card<Destination: View>(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCardBackground(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}
