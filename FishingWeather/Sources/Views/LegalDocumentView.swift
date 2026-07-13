import SwiftUI

struct LegalDocumentView: View {
    let document: LegalDocument

    var body: some View {
        Group {
            switch Result(catching: { try document.load() }) {
            case .success(let body):
                documentBody(body)
            case .failure(let error):
                ContentUnavailableView {
                    Label("Document unavailable", systemImage: "doc.badge.ellipsis")
                } description: {
                    Text(error.localizedDescription)
                }
            }
        }
        .background(Ink.backdrop)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func documentBody(_ body: LegalDocumentBody) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(body.blocks.enumerated()), id: \.offset) { index, block in
                    switch block {
                    case .link(let url):
                        Link(destination: url) {
                            Label(url.absoluteString, systemImage: "arrow.up.right.square")
                                .font(.callout)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityHint("Opens in your browser")
                    case .text(let text):
                        Text(text)
                            .font(font(for: text, at: index))
                            .fontWeight(weight(for: text, at: index))
                            .foregroundStyle(index == 0 ? Ink.chart : Ink.chartDim)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .padding(.bottom, 30)
        }
    }

    private func font(for text: String, at index: Int) -> Font {
        if index == 0 { return .system(.title2, design: .rounded) }
        if text.hasPrefix("Effective ") { return .footnote }
        if isHeading(text) { return .system(.headline, design: .rounded) }
        return .body
    }

    private func weight(for text: String, at index: Int) -> Font.Weight? {
        if index == 0 || isHeading(text) { return .bold }
        return nil
    }

    private func isHeading(_ text: String) -> Bool {
        text.count <= 60
            && !text.contains("\n")
            && !text.contains(".")
            && !text.hasPrefix("Effective ")
    }
}
