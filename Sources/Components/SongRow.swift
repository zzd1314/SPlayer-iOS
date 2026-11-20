import SwiftUI

/// 歌曲行：序号（可选）+ 歌名 + 歌手 · 专辑
struct SongRow: View {
    let index: Int?
    let song: Song

    var body: some View {
        HStack(spacing: 10) {
            if let index {
                Text("\(index)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.name)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        var parts: [String] = []
        if !song.artistText.isEmpty {
            parts.append(song.artistText)
        }
        if let album = song.albumName, !album.isEmpty {
            parts.append(album)
        }
        return parts.joined(separator: " · ")
    }
}
