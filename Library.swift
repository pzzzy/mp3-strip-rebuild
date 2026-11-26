import AVFoundation
import Foundation

enum SortMode: String, CaseIterable {
    case album, artist, folder, file

    var label: String { "By " + rawValue.capitalized }

    func group(for track: Track) -> String {
        switch self {
        case .album: return track.album.isEmpty ? "Unknown Album" : track.album
        case .artist: return track.artist.isEmpty ? "Unknown Artist" : track.artist
        case .folder: return track.folder
        case .file: return ""
        }
    }

    func sorted(_ tracks: [Track]) -> [Track] {
        tracks.sorted { a, b in
            let aKeys = self == .file ? [a.url.lastPathComponent] : [group(for: a), a.title]
            let bKeys = self == .file ? [b.url.lastPathComponent] : [group(for: b), b.title]
            for (left, right) in zip(aKeys, bKeys) {
                let order = left.localizedStandardCompare(right)
                if order != .orderedSame { return order == .orderedAscending }
                if left != right { return left < right }
            }
            return a.url.path < b.url.path
        }
    }
}

struct Track: Encodable {
    let url: URL
    let title: String
    let album: String
    let artist: String
    let folder: String
    let duration: Double

    enum CodingKeys: String, CodingKey {
        case title, album, artist, duration
    }
}

enum Library {
    static let introSeconds = 10

    static func scan(_ root: URL) async throws -> [Track] {
        guard try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
              let files = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
              ) else { throw CocoaError(.fileReadUnknown) }

        var tracks: [Track] = []
        while let url = files.nextObject() as? URL {
            try Task.checkCancellation()
            guard url.pathExtension.lowercased() == "mp3",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let audio = try? AVAudioFile(forReading: url),
                  audio.length > 0, audio.processingFormat.sampleRate > 0 else { continue }
            let asset = AVURLAsset(url: url)
            let metadata = (try? await asset.load(.commonMetadata)) ?? []
            let title = await tag(.commonIdentifierTitle, in: metadata)
            let album = await tag(.commonIdentifierAlbumName, in: metadata)
            let artist = await tag(.commonIdentifierArtist, in: metadata)
            let parent = url.deletingLastPathComponent()
            let relativeFolder = parent.pathComponents.dropFirst(root.pathComponents.count)
            tracks.append(Track(
                url: url, title: title ?? url.deletingPathExtension().lastPathComponent,
                album: album ?? "", artist: artist ?? "",
                folder: relativeFolder.isEmpty ? root.lastPathComponent : relativeFolder.joined(separator: "/"),
                duration: Double(audio.length) / audio.processingFormat.sampleRate
            ))
        }
        return tracks
    }

    private static func tag(_ key: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> String? {
        for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: key) {
            if let value = try? await item.load(.stringValue) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    static func adjacent(to index: Int, step: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        return (index + step + count) % count
    }

    static func decodeSamples(from url: URL) throws -> Int {
        let audio = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4096) else {
            throw CocoaError(.fileReadUnknown)
        }
        try audio.read(into: buffer)
        return Int(buffer.frameLength) * Int(buffer.format.channelCount)
    }
}

struct Verification: Encodable {
    let tracks: [Track]
    let decodeSamples: Int
    let wrappedForward: Bool
    let wrappedBackward: Bool
    let introSeconds: Int

    static func run(folder: String, mode: SortMode) async throws {
        let url = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL
        let tracks = mode.sorted(try await Library.scan(url))
        let count = tracks.count
        let result = Verification(
            tracks: tracks,
            decodeSamples: try tracks.first.map { try Library.decodeSamples(from: $0.url) } ?? 0,
            wrappedForward: Library.adjacent(to: count - 1, step: 1, count: count) == 0,
            wrappedBackward: Library.adjacent(to: 0, step: -1, count: count) == count - 1,
            introSeconds: Library.introSeconds
        )
        var output = try JSONEncoder().encode(result)
        output.append(10)
        FileHandle.standardOutput.write(output)
    }
}
