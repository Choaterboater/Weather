import Foundation
import Testing
@testable import BiteCast

@Suite("YouTubeClient")
struct YouTubeClientTests {
    @Test
    func searchResponseFallsBackToDefaultThumbnailWhenHighIsMissing() throws {
        let json = """
        {
          "items": [
            {
              "id": { "videoId": "abc123" },
              "snippet": {
                "title": "Bass &amp; Bait",
                "channelTitle": "Choate&#39;s Channel",
                "thumbnails": {
                  "default": {
                    "url": "https://i.ytimg.com/vi/abc123/default.jpg"
                  }
                }
              }
            }
          ]
        }
        """

        let videos = try YouTubeClient.videos(from: Data(json.utf8))

        #expect(videos == [
            YouTubeVideo(
                id: "abc123",
                title: "Bass & Bait",
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/abc123/default.jpg"),
                channelTitle: "Choate's Channel"
            )
        ])
    }
}
