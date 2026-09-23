import Foundation

/// Manual "Check for updates" against the GitHub Releases API.
///
/// Pure logic (semver compare, JSON parsing, Homebrew detection) is static
/// and unit-tested with fixtures; `check(...)` is the only networked entry
/// point and is never called at launch, only from the Settings button.
public enum UpdateChecker {
    public enum CheckResult: Equatable, Sendable {
        case upToDate
        case updateAvailable(version: String, url: URL)
        case failed(message: String)
    }

    /// Subset of the GitHub "latest release" payload we use.
    private struct LatestRelease: Decodable {
        let tag_name: String
        let html_url: String
    }

    /// Parse the latest-release JSON into (version without "v" prefix,
    /// release page URL). Returns nil for malformed payloads.
    public static func parseLatestRelease(_ data: Data) -> (version: String, url: URL)? {
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: data),
              let url = URL(string: release.html_url) else { return nil }
        var version = release.tag_name
        if version.hasPrefix("v") { version.removeFirst() }
        guard !version.isEmpty else { return nil }
        return (version, url)
    }

    /// Numeric component comparison: "1.10.0" is newer than "1.9.0".
    /// Missing components pad as 0; non-numeric components read as 0, so a
    /// garbage tag never reports itself as an update.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Select the version that can be compared with
    /// `CFBundleShortVersionString`. Sparkle's short version is the marketing
    /// version; `sparkle:version` is only a fallback when no short version is
    /// available anywhere in the appcast.
    public static func preferredAppcastVersion(
        shortVersion: String?,
        buildVersion: String?
    ) -> String? {
        shortVersion ?? buildVersion
    }

    /// Caskroom locations for Apple Silicon and Intel Homebrew prefixes.
    public static let defaultCaskroomPaths = [
        "/opt/homebrew/Caskroom/catcleaner",
        "/usr/local/Caskroom/catcleaner",
    ]

    /// True when the app was installed via the Homebrew cask. The Settings
    /// UI will show `brew upgrade --cask catcleaner` instead of a DMG link,
    /// so brew's receipt and the installed app never drift.
    public static func isHomebrewInstall(
        caskroomPaths: [String] = defaultCaskroomPaths,
        fileManager: FileManager = .default
    ) -> Bool {
        caskroomPaths.contains { fileManager.fileExists(atPath: $0) }
    }

    /// Where to look for the latest version, per install source. This remains
    /// nil while CatCleaner has no owned release feed. A future Homebrew build
    /// will use the CatCleaner cask API; direct/DMG installs will use a
    /// CatCleaner-owned release endpoint.
    public static func updateSourceURL(isHomebrew: Bool) -> URL? {
        guard MCConstants.updateChecksEnabled else { return nil }
        return isHomebrew ? MCConstants.homebrewCaskAPI : MCConstants.latestReleaseAPI
    }

    /// Parse the `version` from Homebrew's cask JSON (formulae.brew.sh).
    /// Returns nil for malformed payloads or `:latest` casks (no comparable
    /// version).
    public static func parseCaskVersion(_ data: Data) -> String? {
        struct Cask: Decodable { let version: String }
        guard let cask = try? JSONDecoder().decode(Cask.self, from: data),
              !cask.version.isEmpty, cask.version != ":latest" else { return nil }
        return cask.version
    }

    /// Check for a newer version and classify the result. Homebrew installs
    /// compare against the official cask version so the prompt matches what
    /// `brew upgrade` can install; everyone else compares against the latest
    /// GitHub release. Failures are returned as values, never thrown.
    public static func check(
        currentVersion: String = MCConstants.appVersion,
        session: URLSession = .shared,
        isHomebrew: Bool = isHomebrewInstall()
    ) async -> CheckResult {
        guard MCConstants.updateChecksEnabled,
              let sourceURL = updateSourceURL(isHomebrew: isHomebrew)
        else {
            return .failed(message: L10n.tr(
                "CatCleaner 更新通道尚未配置。",
                "CatCleaner update channel is not configured yet.",
                "Канал обновлений CatCleaner пока не настроен."
            ))
        }

        var request = URLRequest(url: sourceURL, timeoutInterval: 10)
        request.setValue(
            isHomebrew ? "application/json" : "application/vnd.github+json",
            forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await session.data(for: request)
            let version: String
            let url: URL
            if isHomebrew {
                guard let caskVersion = parseCaskVersion(data) else {
                    return .failed(message: L10n.tr("Homebrew 返回了无法识别的响应。", "Unexpected response from Homebrew.", "Неожиданный ответ от Homebrew."))
                }
                version = caskVersion
                // Brew installs act via `brew upgrade`, not a download link;
                // the releases page is a sensible fallback URL.
                guard let releasesURL = MCConstants.releasesURL else {
                    return .failed(message: L10n.tr(
                        "CatCleaner Homebrew 更新通道尚未配置。",
                        "CatCleaner Homebrew update channel is not configured yet.",
                        "Канал обновлений CatCleaner через Homebrew пока не настроен."
                    ))
                }
                url = releasesURL
            } else {
                guard let parsed = parseLatestRelease(data) else {
                    return .failed(message: L10n.tr("GitHub 返回了无法识别的响应。", "Unexpected response from GitHub.", "Неожиданный ответ от GitHub."))
                }
                version = parsed.version
                url = parsed.url
            }
            return isNewer(version, than: currentVersion)
                ? .updateAvailable(version: version, url: url)
                : .upToDate
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }
}
