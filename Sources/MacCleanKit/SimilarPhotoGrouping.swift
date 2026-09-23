import Foundation

public struct SimilarPhotoAsset: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let fileSize: UInt64
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let creationDate: Date?
    public let modificationDate: Date?

    public init(
        id: UUID = UUID(),
        url: URL,
        fileSize: UInt64,
        pixelWidth: Int,
        pixelHeight: Int,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.fileSize = fileSize
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }

    public var aspectRatio: Double {
        guard pixelWidth > 0, pixelHeight > 0 else { return 0 }
        return Double(pixelWidth) / Double(pixelHeight)
    }

    public var pixelCount: UInt64 {
        UInt64(max(0, pixelWidth)) * UInt64(max(0, pixelHeight))
    }
}

/// A Vision-derived distance between two image feature prints.
///
/// Smaller values mean greater similarity. CatCleaner intentionally keeps the
/// threshold outside this type because Vision does not define one universal
/// "duplicate photo" cutoff.
public struct SimilarPhotoPair: Hashable, Sendable {
    public let first: URL
    public let second: URL
    public let distance: Float

    public init(first: URL, second: URL, distance: Float) {
        if first.path(percentEncoded: false) <= second.path(percentEncoded: false) {
            self.first = first
            self.second = second
        } else {
            self.first = second
            self.second = first
        }
        self.distance = distance
    }
}

public struct SimilarPhotoComparison: Hashable, Sendable {
    public let first: SimilarPhotoAsset
    public let second: SimilarPhotoAsset

    public init(first: SimilarPhotoAsset, second: SimilarPhotoAsset) {
        if first.url.path(percentEncoded: false) <= second.url.path(percentEncoded: false) {
            self.first = first
            self.second = second
        } else {
            self.first = second
            self.second = first
        }
    }
}

public struct SimilarPhotoClusterMember: Hashable, Sendable {
    public let asset: SimilarPhotoAsset
    public let distanceToAnchor: Float

    public init(asset: SimilarPhotoAsset, distanceToAnchor: Float) {
        self.asset = asset
        self.distanceToAnchor = distanceToAnchor
    }
}

public struct SimilarPhotoCluster: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let anchor: SimilarPhotoAsset
    public let members: [SimilarPhotoClusterMember]

    public init(
        id: UUID = UUID(),
        anchor: SimilarPhotoAsset,
        members: [SimilarPhotoClusterMember]
    ) {
        self.id = id
        self.anchor = anchor
        self.members = members
    }

    public var allAssets: [SimilarPhotoAsset] {
        [anchor] + members.map(\.asset)
    }

    public var count: Int { members.count + 1 }

    public var closestDistance: Float {
        members.map(\.distanceToAnchor).min() ?? 0
    }

    public var farthestDistance: Float {
        members.map(\.distanceToAnchor).max() ?? 0
    }
}

/// Pure policy and grouping logic for review-only similar-photo results.
public enum SimilarPhotoGrouping {
    public static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tif", "tiff", "webp"
    ]

    /// A conservative starting point for the review UI, not an Apple-defined
    /// semantic boundary. The UI should let this be calibrated before any
    /// future cleanup action is considered.
    public static let reviewMaximumDistance: Float = 0.30

    public static func isSupportedImage(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Cheap metadata prefilter before feature-print distance computation.
    ///
    /// Near-duplicate exports can be resized substantially, so pixel count is
    /// allowed to vary by 8x. Aspect ratio is tighter because crops beyond this
    /// point are more likely to be a distinct composition and can be reviewed
    /// separately with a more permissive mode later.
    public static func shouldCompare(
        _ lhs: SimilarPhotoAsset,
        _ rhs: SimilarPhotoAsset,
        maximumAspectRatioDelta: Double = 0.08,
        maximumPixelCountRatio: Double = 8.0
    ) -> Bool {
        guard lhs.url != rhs.url,
              lhs.pixelWidth > 0, lhs.pixelHeight > 0,
              rhs.pixelWidth > 0, rhs.pixelHeight > 0
        else { return false }

        let aspectDelta = abs(lhs.aspectRatio - rhs.aspectRatio)
        guard aspectDelta <= maximumAspectRatioDelta else { return false }

        let smaller = min(lhs.pixelCount, rhs.pixelCount)
        let larger = max(lhs.pixelCount, rhs.pixelCount)
        guard smaller > 0 else { return false }

        return Double(larger) / Double(smaller) <= maximumPixelCountRatio
    }

    private struct ComparisonKey: Hashable {
        let first: URL
        let second: URL
    }

    /// Plans a bounded set of feature-print comparisons from metadata.
    ///
    /// This keeps the Vision layer from degenerating into an unbounded O(n²)
    /// workload on a large photo library. Each asset gets only its most
    /// plausible partners, ranked by aspect ratio, resolution, file size, and
    /// capture/file-date proximity. The output is deterministic.
    public static func comparisonPlan(
        assets: [SimilarPhotoAsset],
        maxPartnersPerAsset: Int = 48,
        maxTotalPairs: Int = 50_000
    ) -> [SimilarPhotoComparison] {
        guard assets.count > 1,
              maxPartnersPerAsset > 0,
              maxTotalPairs > 0
        else { return [] }

        let ordered = assets.sorted {
            $0.url.path(percentEncoded: false) < $1.url.path(percentEncoded: false)
        }

        var output: [SimilarPhotoComparison] = []
        output.reserveCapacity(min(maxTotalPairs, ordered.count * min(maxPartnersPerAsset, 8)))
        var seen: Set<ComparisonKey> = []

        for (index, asset) in ordered.enumerated() {
            if output.count >= maxTotalPairs { break }

            let ranked = ordered[(index + 1)...]
                .filter { shouldCompare(asset, $0) }
                .map { other in
                    (asset: other, score: metadataSimilarityScore(asset, other))
                }
                .sorted {
                    if $0.score == $1.score {
                        return $0.asset.url.path(percentEncoded: false)
                            < $1.asset.url.path(percentEncoded: false)
                    }
                    return $0.score < $1.score
                }
                .prefix(maxPartnersPerAsset)

            for entry in ranked {
                if output.count >= maxTotalPairs { break }

                let comparison = SimilarPhotoComparison(first: asset, second: entry.asset)
                let key = ComparisonKey(
                    first: comparison.first.url,
                    second: comparison.second.url
                )
                guard seen.insert(key).inserted else { continue }
                output.append(comparison)
            }
        }

        return output
    }

    private static func metadataSimilarityScore(
        _ lhs: SimilarPhotoAsset,
        _ rhs: SimilarPhotoAsset
    ) -> Double {
        let aspect = abs(lhs.aspectRatio - rhs.aspectRatio)

        let minPixels = max(UInt64(1), min(lhs.pixelCount, rhs.pixelCount))
        let maxPixels = max(lhs.pixelCount, rhs.pixelCount)
        let pixelRatio = Double(maxPixels) / Double(minPixels)
        let pixelScore = abs(log(pixelRatio))

        let minBytes = max(UInt64(1), min(lhs.fileSize, rhs.fileSize))
        let maxBytes = max(lhs.fileSize, rhs.fileSize)
        let byteRatio = Double(maxBytes) / Double(minBytes)
        let byteScore = abs(log(byteRatio))

        let lhsDate = lhs.creationDate ?? lhs.modificationDate
        let rhsDate = rhs.creationDate ?? rhs.modificationDate
        let dateScore: Double
        if let lhsDate, let rhsDate {
            // Dates only rank candidates; they never exclude a pair.
            dateScore = min(abs(lhsDate.timeIntervalSince(rhsDate)) / (365 * 86_400), 1)
        } else {
            dateScore = 0.5
        }

        return aspect * 8 + pixelScore * 0.8 + byteScore * 0.25 + dateScore * 0.4
    }

    /// Builds conservative complete-link review groups.
    ///
    /// Every pair of photos inside a group must have a measured Vision distance
    /// at or below the threshold. A missing pair is treated as insufficient
    /// evidence and therefore cannot join the same group. This prevents
    /// similarity chains such as A≈B and B≈C from grouping A/B/C when A and C
    /// are not themselves similar.
    public static func clusters(
        assets: [SimilarPhotoAsset],
        pairs: [SimilarPhotoPair],
        maximumDistance: Float = reviewMaximumDistance
    ) -> [SimilarPhotoCluster] {
        guard assets.count > 1, maximumDistance >= 0 else { return [] }

        let assetByURL = Dictionary(
            assets.map { ($0.url, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var distanceByPair: [ComparisonKey: Float] = [:]
        for pair in pairs {
            guard pair.first != pair.second,
                  pair.distance.isFinite,
                  pair.distance >= 0,
                  assetByURL[pair.first] != nil,
                  assetByURL[pair.second] != nil
            else { continue }

            let key = ComparisonKey(first: pair.first, second: pair.second)
            if let existing = distanceByPair[key] {
                distanceByPair[key] = min(existing, pair.distance)
            } else {
                distanceByPair[key] = pair.distance
            }
        }

        func pairKey(_ lhs: URL, _ rhs: URL) -> ComparisonKey {
            if lhs.path(percentEncoded: false) <= rhs.path(percentEncoded: false) {
                return ComparisonKey(first: lhs, second: rhs)
            }
            return ComparisonKey(first: rhs, second: lhs)
        }

        func distance(_ lhs: URL, _ rhs: URL) -> Float? {
            guard lhs != rhs else { return 0 }
            return distanceByPair[pairKey(lhs, rhs)]
        }

        var unassigned = Set(assetByURL.keys)
        var output: [SimilarPhotoCluster] = []

        while true {
            let seed = distanceByPair
                .compactMap { entry -> (key: ComparisonKey, distance: Float)? in
                    guard entry.value <= maximumDistance,
                          unassigned.contains(entry.key.first),
                          unassigned.contains(entry.key.second)
                    else { return nil }
                    return (entry.key, entry.value)
                }
                .sorted {
                    if $0.distance != $1.distance {
                        return $0.distance < $1.distance
                    }
                    let lhsFirst = $0.key.first.path(percentEncoded: false)
                    let rhsFirst = $1.key.first.path(percentEncoded: false)
                    if lhsFirst != rhsFirst { return lhsFirst < rhsFirst }
                    return $0.key.second.path(percentEncoded: false)
                        < $1.key.second.path(percentEncoded: false)
                }
                .first

            guard let seed else { break }

            var groupURLs = [seed.key.first, seed.key.second]
            var available = unassigned
            available.remove(seed.key.first)
            available.remove(seed.key.second)

            while true {
                let candidate = available.compactMap {
                    url -> (url: URL, maxDistance: Float, sumDistance: Float)? in
                    var distances: [Float] = []
                    distances.reserveCapacity(groupURLs.count)

                    for memberURL in groupURLs {
                        guard let measured = distance(url, memberURL),
                              measured <= maximumDistance
                        else {
                            return nil
                        }
                        distances.append(measured)
                    }

                    guard let maxDistance = distances.max() else { return nil }
                    return (url, maxDistance, distances.reduce(0, +))
                }
                .sorted {
                    if $0.maxDistance != $1.maxDistance {
                        return $0.maxDistance < $1.maxDistance
                    }
                    if $0.sumDistance != $1.sumDistance {
                        return $0.sumDistance < $1.sumDistance
                    }
                    return $0.url.path(percentEncoded: false)
                        < $1.url.path(percentEncoded: false)
                }
                .first

                guard let candidate else { break }
                groupURLs.append(candidate.url)
                available.remove(candidate.url)
            }

            let anchorURL = groupURLs.min { lhs, rhs in
                func metrics(_ candidate: URL) -> (max: Float, sum: Float) {
                    let values = groupURLs
                        .filter { $0 != candidate }
                        .compactMap { distance(candidate, $0) }
                    return (values.max() ?? 0, values.reduce(0, +))
                }

                let lhsMetrics = metrics(lhs)
                let rhsMetrics = metrics(rhs)
                if lhsMetrics.max != rhsMetrics.max {
                    return lhsMetrics.max < rhsMetrics.max
                }
                if lhsMetrics.sum != rhsMetrics.sum {
                    return lhsMetrics.sum < rhsMetrics.sum
                }
                return lhs.path(percentEncoded: false)
                    < rhs.path(percentEncoded: false)
            } ?? seed.key.first

            guard let anchor = assetByURL[anchorURL] else {
                unassigned.subtract(groupURLs)
                continue
            }

            let members = groupURLs
                .filter { $0 != anchorURL }
                .compactMap { url -> SimilarPhotoClusterMember? in
                    guard let asset = assetByURL[url],
                          let measured = distance(anchorURL, url)
                    else { return nil }
                    return SimilarPhotoClusterMember(
                        asset: asset,
                        distanceToAnchor: measured
                    )
                }
                .sorted {
                    if $0.distanceToAnchor != $1.distanceToAnchor {
                        return $0.distanceToAnchor < $1.distanceToAnchor
                    }
                    return $0.asset.url.path(percentEncoded: false)
                        < $1.asset.url.path(percentEncoded: false)
                }

            unassigned.subtract(groupURLs)
            output.append(
                SimilarPhotoCluster(
                    anchor: anchor,
                    members: members
                )
            )
        }

        return output.sorted {
            if $0.count == $1.count {
                if $0.farthestDistance == $1.farthestDistance {
                    return $0.anchor.url.path(percentEncoded: false)
                        < $1.anchor.url.path(percentEncoded: false)
                }
                return $0.farthestDistance < $1.farthestDistance
            }
            return $0.count > $1.count
        }
    }
}
