import SwiftUI

/// 网络封面图（带占位与失败态）
struct CoverImage: View {
    let urlString: String?
    var size: CGFloat = 52
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else if phase.error != nil {
                        placeholder
                    } else {
                        ZStack {
                            placeholder
                            ProgressView()
                        }
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Color(.tertiarySystemFill)
            Image(systemName: "music.note")
                .foregroundStyle(.secondary)
        }
    }
}
