import Foundation

@MainActor
@Observable
final class YouTubeClient {
    enum Status: Equatable {
        case idle
        case working
        case ready([YouTubeVideo])
        case failed(String)
    }

    private(set) var status: Status = .idle

    func search(query: String) async {
        status = .working

        guard let apiKey = AppSecrets.youtubeAPIKey, !apiKey.isEmpty, apiKey != "your_youtube_api_key_here" else {
            // Mock data for previewing when no API key is provided
            try? await Task.sleep(for: .seconds(1))
            self.status = .ready([
                YouTubeVideo(
                    id: "dQw4w9WgXcQ",
                    title: "Best setup for \(query)?",
                    thumbnailURL: nil,
                    channelTitle: "BiteCast Fishing"
                ),
                YouTubeVideo(
                    id: "jNQXAC9IVRw",
                    title: "Watch me land a monster! | \(query)",
                    thumbnailURL: nil,
                    channelTitle: "Angler's Digest"
                ),
                YouTubeVideo(
                    id: "V-_O7nl0Ii0",
                    title: "Secret \(query) spot REVEALED",
                    thumbnailURL: nil,
                    channelTitle: "Local Legends"
                )
            ])
            return
        }

        guard var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search") else {
            self.status = .failed("Invalid search query.")
            return
        }
        components.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "maxResults", value: "5"),
            URLQueryItem(name: "key", value: apiKey)
        ]
        guard let url = components.url else {
            self.status = .failed("Invalid search query.")
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                self.status = .failed("Failed to connect to YouTube.")
                return
            }

            let searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
            let videos = searchResponse.items.compactMap { item -> YouTubeVideo? in
                guard let id = item.id.videoId else { return nil }
                return YouTubeVideo(
                    id: id,
                    title: item.snippet.title.stringByDecodingHTMLEntities,
                    thumbnailURL: URL(string: item.snippet.thumbnails.high.url ?? item.snippet.thumbnails.default.url),
                    channelTitle: item.snippet.channelTitle.stringByDecodingHTMLEntities
                )
            }
            self.status = .ready(videos)
        } catch {
            self.status = .failed(error.localizedDescription)
        }
    }

    private struct SearchResponse: Decodable {
        let items: [Item]

        struct Item: Decodable {
            let id: ID
            let snippet: Snippet

            struct ID: Decodable {
                let videoId: String?
            }

            struct Snippet: Decodable {
                let title: String
                let channelTitle: String
                let thumbnails: Thumbnails

                struct Thumbnails: Decodable {
                    let `default`: Thumbnail
                    let high: Thumbnail

                    struct Thumbnail: Decodable {
                        let url: String
                    }
                }
            }
        }
    }
}

// Super simple, limited HTML entity un-escaping for YouTube titles
private extension String {
    var stringByDecodingHTMLEntities: String {
        self.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
