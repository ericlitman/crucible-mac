import Foundation

nonisolated struct NotificationPayload: Equatable, Sendable {
    let episodeID: String
    let requestIdentifier: String
    let title: String
    let subtitle: String
    let body: String
    let userInfo: [String: String]
}
