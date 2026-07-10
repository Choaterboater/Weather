import Foundation

struct YouTubeVideo: Identifiable, Equatable {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let channelTitle: String

    var videoURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(id)")!
    }
}
