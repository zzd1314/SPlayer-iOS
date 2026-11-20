import SwiftUI

/// 歌手介绍：简介 + 分段介绍
struct ArtistDescriptionView: View {
    let name: String
    let brief: String?
    let paragraphs: [ArtistDescResponse.Paragraph]

    var body: some View {
        List {
            if let brief, !brief.isEmpty {
                Section("简介") {
                    Text(brief)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }

            ForEach(paragraphs.indices, id: \.self) { index in
                let paragraph = paragraphs[index]
                if let txt = paragraph.txt, !txt.isEmpty {
                    Section(paragraphTitle(paragraph)) {
                        Text(txt)
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .listStyle(.plain)
        .adaptiveListBackground()
        .navigationTitle("歌手介绍")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func paragraphTitle(_ paragraph: ArtistDescResponse.Paragraph) -> String {
        guard let title = paragraph.ti, !title.isEmpty else { return "介绍" }
        return title
    }
}
