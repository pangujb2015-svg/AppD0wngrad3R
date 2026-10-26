import Foundation

/// Removes app extensions (.appex) that iOS would reject at install time
/// (e.g. widgets built for a newer iOS: "AppexBundleMissingClassOrStoryboard").
/// The modified IPA only installs on devices that skip signature checks
/// (jailbroken with AppSync Unified, etc.).
enum IPASanitizer {
    static let enabledKey = "stripIncompatibleExtensions"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false
    }

    struct Result {
        let path: String
        let removed: [String]
    }

    /// Returns the path to install. If nothing had to be removed, this is the original path.
    static func stripBrokenExtensions(ipaPath: String) async throws -> Result {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("AppDowngraderClean-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workDir) }

        let unzip = try await Shell.run(
            "unzip", arguments: ["-q", ipaPath, "-d", workDir.path], timeout: 300
        )
        guard unzip.succeeded else {
            throw NSError(domain: "IPASanitizer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "unzip failed: \(unzip.stderr)"])
        }

        let payload = workDir.appendingPathComponent("Payload")
        var removed: [String] = []

        let appDirs = (try? fm.contentsOfDirectory(atPath: payload.path))?
            .filter { $0.hasSuffix(".app") } ?? []
        for appDir in appDirs {
            let plugIns = payload.appendingPathComponent(appDir).appendingPathComponent("PlugIns")
            let appexes = (try? fm.contentsOfDirectory(atPath: plugIns.path))?
                .filter { $0.hasSuffix(".appex") } ?? []
            for appex in appexes {
                let appexURL = plugIns.appendingPathComponent(appex)
                if !hasValidEntryPoint(appexURL) {
                    try fm.removeItem(at: appexURL)
                    removed.append(appex)
                }
            }
        }

        guard !removed.isEmpty else {
            return Result(path: ipaPath, removed: [])
        }

        let outPath = ipaPath.replacingOccurrences(of: ".ipa", with: "_clean.ipa")
        try? fm.removeItem(atPath: outPath)

        let script = "cd \(shellQuote(workDir.path)) && zip -qry \(shellQuote(outPath)) Payload"
        let zip = try await Shell.run("sh", arguments: ["-c", script], timeout: 300)
        guard zip.succeeded else {
            throw NSError(domain: "IPASanitizer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "zip failed: \(zip.stderr)"])
        }
        return Result(path: outPath, removed: removed)
    }

    /// iOS requires NSExtensionPrincipalClass or NSExtensionMainStoryboard (a non-empty string).
    private static func hasValidEntryPoint(_ appex: URL) -> Bool {
        let plistURL = appex.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let ext = dict["NSExtension"] as? [String: Any]
        else { return true } // unreadable: leave it alone
        let principal = ext["NSExtensionPrincipalClass"] as? String ?? ""
        let storyboard = ext["NSExtensionMainStoryboard"] as? String ?? ""
        return !principal.isEmpty || !storyboard.isEmpty
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
