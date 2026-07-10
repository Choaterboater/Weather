import SwiftUI

/// Reusable horizontal scrolling list of YouTube video cards.
struct YouTubeVideoCarousel: View {
    let title: String
    let query: String
    @State private var client = YouTubeClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, systemImage: "play.tv")
            
            switch client.status {
            case .idle, .working:
                GlassCard {
                    HStack {
                        ProgressView()
                        Text("Searching YouTube…")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .failed(let message):
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Couldn't load videos", systemImage: "wifi.slash")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                        Text(message)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                        Button("Retry") {
                            Task { await client.search(query: query) }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                }
            case .ready(let videos):
                if videos.isEmpty {
                    GlassCard {
                        Text("No videos found.")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(videos) { video in
                                YouTubeVideoCard(video: video)
                            }
                        }
                    }
                }
            }
        }
        .task(id: query) {
            await client.search(query: query)
        }
    }
}

private struct YouTubeVideoCard: View {
    let video: YouTubeVideo

    var body: some View {
        Link(destination: video.videoURL) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    thumbnail
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Ink.chart)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(video.channelTitle)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Ink.chartDim)
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 220)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = video.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                default:
                    placeholder.overlay { ProgressView() }
                }
            }
            .frame(height: 120)
            .clipShape(.rect(cornerRadius: 12))
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Ink.hullLine.opacity(0.3), Ink.abyss.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 120)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Ink.hullLine, lineWidth: 1)
        )
        .overlay {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Ink.chartDim.opacity(0.5))
        }
    }
}
