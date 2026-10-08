import Foundation
import MusicKit
import Soundscape

enum MusicSourceError: Error { case nothingFound }

/// Apple Music for a focus session: a personal recommendation that fits
/// the mood when there is one, else an Apple-curated catalog playlist.
@MainActor
final class MusicSource {
    private(set) var playlistName: String?
    private let player = ApplicationMusicPlayer.shared

    func availability() async -> MusicAvailability {
        let status = MusicAuthorization.currentStatus == .notDetermined
            ? await MusicAuthorization.request() : MusicAuthorization.currentStatus
        guard status == .authorized else { return .denied }
        guard let subscription = try? await MusicSubscription.current else { return .unknown }
        return subscription.canPlayCatalogContent ? .available : .notSubscribed
    }

    func play(_ mood: Mood) async throws {
        let playlist = try await pick(for: mood)
        playlistName = playlist.name
        player.queue = [playlist]
        player.state.repeatMode = .all
        try await Self.play()
    }

    func pause() { player.pause() }
    func resume() async { try? await Self.play() }

    /// The player is not Sendable, so the async `play()` runs where the
    /// shared player is read, rather than being sent off the main actor.
    nonisolated private static func play() async throws { try await ApplicationMusicPlayer.shared.play() }
    func stop() { player.stop(); playlistName = nil }

    private func pick(for mood: Mood) async throws -> Playlist {
        if let personal = try? await MusicPersonalRecommendationsRequest().response() {
            for recommendation in personal.recommendations {
                if let match = recommendation.playlists.first(where: { playlist in
                    mood.musicKeywords.contains { playlist.name.localizedCaseInsensitiveContains($0) }
                }) { return match }
            }
        }
        var search = MusicCatalogSearchRequest(term: mood.musicSearchTerm, types: [Playlist.self])
        search.limit = 15
        let found = try await search.response().playlists
        if let curated = found.first(where: { $0.curatorName == "Apple Music" }) { return curated }
        guard let any = found.first else { throw MusicSourceError.nothingFound }
        return any
    }
}
