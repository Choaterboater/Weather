import SwiftUI

struct LegalCenterView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InstrumentPanel {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(.title2, design: .rounded, weight: .semibold))
                            .foregroundStyle(Ink.brass)
                            .frame(width: 48, height: 48)
                            .background(Ink.brass.opacity(0.12), in: .circle)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Clear about your data")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(Ink.chart)
                            Text("These documents are stored in the app, so privacy, safety, and support details remain readable offline.")
                                .font(.subheadline)
                                .foregroundStyle(Ink.chartDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Documents", systemImage: "doc.text.magnifyingglass")
                    InstrumentPanel {
                        VStack(spacing: 0) {
                            ForEach(Array(LegalDocument.allCases.enumerated()), id: \.element.id) {
                                index, document in
                                NavigationLink {
                                    LegalDocumentView(document: document)
                                } label: {
                                    legalRow(document)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(document.accessibilityIdentifier)
                                .accessibilityLabel(document.title)
                                .accessibilityHint(document.summary)

                                if index < LegalDocument.allCases.count - 1 {
                                    Divider()
                                        .overlay(Ink.hullLine.opacity(0.7))
                                        .padding(.leading, 46)
                                }
                            }
                        }
                    }
                }

                if let supportURL = LegalDocument.support.externalURL {
                    Link(destination: supportURL) {
                        Label("Open project support page", systemImage: "arrow.up.right.square")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Ink.brass)
                    .accessibilityIdentifier("legal.support.external")
                }

                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(Ink.chartDim)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(versionLine)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Ink.backdrop)
        .navigationTitle("Legal & Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func legalRow(_ document: LegalDocument) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.systemImage)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(Ink.brass)
                .frame(width: 34, height: 34)
                .background(Ink.brass.opacity(0.1), in: .rect(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Ink.chart)
                Text(document.summary)
                    .font(.caption)
                    .foregroundStyle(Ink.chartDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Ink.chartDim)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .contentShape(.rect)
    }

    private var versionLine: String {
        let dictionary = Bundle.main.infoDictionary
        let version = dictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = dictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "BiteCast \(version) (\(build))"
    }
}
