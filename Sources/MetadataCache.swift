import Foundation

/// Disk-backed cache for immutable version metadata.
/// Stored at ~/Library/Caches/AppDowngrader/version-metadata.json
actor MetadataCache {
    static let shared = MetadataCache()

    // "bundleId|externalVersionId" -> metadata. External version IDs are only
    // unique within one app, so the bundle ID has to be part of the key.
    private var cache: [String: VersionMetadata] = [:]

    private let fileURL: URL

    private init() {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppDowngrader", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let url = cacheDir.appendingPathComponent("version-metadata.json")
        fileURL = url

        // Older builds cached bare version-ID -> display-version pairs. Those keys
        // are ambiguous, so they are dropped and refetched once.
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: VersionMetadata].self, from: data) {
            cache = decoded
        }
    }

    func get(bundleId: String, versionId: String) -> VersionMetadata? {
        cache[Self.key(bundleId: bundleId, versionId: versionId)]
    }

    func set(bundleId: String, versionId: String, metadata: VersionMetadata) {
        cache[Self.key(bundleId: bundleId, versionId: versionId)] = metadata
        save()
    }

    private static func key(bundleId: String, versionId: String) -> String {
        "\(bundleId)|\(versionId)"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
