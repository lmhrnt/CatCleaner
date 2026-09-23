import Foundation
import CoreGraphics
import ImageIO
import Vision
import MacCleanKit

struct SimilarPhotoScanReport: Sendable {
    let assets: [SimilarPhotoAsset]
    let pairs: [SimilarPhotoPair]
    let candidateCount: Int
    let featureCount: Int
    let comparedPairCount: Int
    let featureFailureCount: Int
    let truncatedCandidateCount: Int

    func clusters(maximumDistance: Float) -> [SimilarPhotoCluster] {
        SimilarPhotoGrouping.clusters(
            assets: assets,
            pairs: pairs,
            maximumDistance: maximumDistance
        )
    }
}

struct SimilarPhotosModule {
    static let maximumAssets = 2_000
    static let maximumFeatureConcurrency = 4

    private let scanner = TargetedScanner()

    private var scanTargets: [ScanTarget] {
        let home = MCConstants.home
        let imageExtensions = SimilarPhotoGrouping.supportedExtensions

        return [
            home.appending(path: "Pictures"),
            home.appending(path: "Desktop"),
            home.appending(path: "Downloads"),
        ].map {
            ScanTarget(
                path: $0,
                recursive: true,
                maxDepth: 8,
                fileExtensions: imageExtensions,
                minSize: 32 * 1024,
                excludePatterns: ["node_modules"],
                skipHiddenDirectories: true
            )
        }
    }

    func scan() async -> SimilarPhotoScanReport {
        let items = await scanner.scan(targets: scanTargets)
        let files = items.filter {
            !$0.isDirectory && SimilarPhotoGrouping.isSupportedImage($0.url)
        }

        let allAssets = files.compactMap(Self.assetMetadata)
            .sorted { lhs, rhs in
                let leftDate = lhs.creationDate ?? lhs.modificationDate ?? .distantPast
                let rightDate = rhs.creationDate ?? rhs.modificationDate ?? .distantPast
                if leftDate == rightDate {
                    return lhs.url.path(percentEncoded: false)
                        < rhs.url.path(percentEncoded: false)
                }
                return leftDate > rightDate
            }

        let assets = Array(allAssets.prefix(Self.maximumAssets))
        let truncated = max(0, allAssets.count - assets.count)

        let plan = SimilarPhotoGrouping.comparisonPlan(assets: assets)
        guard !plan.isEmpty else {
            return SimilarPhotoScanReport(
                assets: assets,
                pairs: [],
                candidateCount: assets.count,
                featureCount: 0,
                comparedPairCount: 0,
                featureFailureCount: 0,
                truncatedCandidateCount: truncated
            )
        }

        let requiredURLs = Set(
            plan.flatMap { [$0.first.url, $0.second.url] }
        )
        let requiredAssets = assets.filter { requiredURLs.contains($0.url) }

        let featureResult = await Self.generateFeatures(
            for: requiredAssets,
            maxConcurrent: Self.maximumFeatureConcurrency
        )

        let pairs = Self.computeDistances(
            plan: plan,
            features: featureResult.features
        )

        return SimilarPhotoScanReport(
            assets: assets,
            pairs: pairs,
            candidateCount: assets.count,
            featureCount: featureResult.features.count,
            comparedPairCount: pairs.count,
            featureFailureCount: featureResult.failureCount,
            truncatedCandidateCount: truncated
        )
    }

    // MARK: - Metadata

    private static func assetMetadata(_ item: FileItem) -> SimilarPhotoAsset? {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0
        else {
            return nil
        }

        return SimilarPhotoAsset(
            url: item.url,
            fileSize: item.size,
            pixelWidth: width,
            pixelHeight: height,
            creationDate: item.creationDate,
            modificationDate: item.modificationDate
        )
    }

    // MARK: - Feature extraction

    private final class FeatureBox: @unchecked Sendable {
        let observation: VNFeaturePrintObservation

        init(_ observation: VNFeaturePrintObservation) {
            self.observation = observation
        }
    }

    private struct FeatureResult: Sendable {
        let features: [URL: FeatureBox]
        let failureCount: Int
    }

    private struct FeatureTaskResult: Sendable {
        let url: URL
        let feature: FeatureBox?
    }

    private static func generateFeatures(
        for assets: [SimilarPhotoAsset],
        maxConcurrent: Int
    ) async -> FeatureResult {
        guard !assets.isEmpty else {
            return FeatureResult(features: [:], failureCount: 0)
        }

        let concurrency = min(max(1, maxConcurrent), assets.count)

        return await withTaskGroup(of: FeatureTaskResult.self) { group in
            var nextIndex = 0
            var features: [URL: FeatureBox] = [:]
            var failures = 0

            func submit(_ asset: SimilarPhotoAsset) {
                group.addTask {
                    if Task.isCancelled {
                        return FeatureTaskResult(url: asset.url, feature: nil)
                    }

                    let feature = featurePrint(for: asset.url)
                    if Task.isCancelled {
                        return FeatureTaskResult(url: asset.url, feature: nil)
                    }

                    return FeatureTaskResult(
                        url: asset.url,
                        feature: feature
                    )
                }
            }

            while nextIndex < concurrency {
                submit(assets[nextIndex])
                nextIndex += 1
            }

            while let result = await group.next() {
                if let feature = result.feature {
                    features[result.url] = feature
                } else {
                    failures += 1
                }

                if nextIndex < assets.count {
                    submit(assets[nextIndex])
                    nextIndex += 1
                }
            }

            return FeatureResult(features: features, failureCount: failures)
        }
    }

    private static func featurePrint(for url: URL) -> FeatureBox? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision1
        request.imageCropAndScaleOption = .scaleFit

        let handler = VNImageRequestHandler(url: url, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            return FeatureBox(observation)
        } catch {
            return nil
        }
    }

    // MARK: - Distances

    private static func computeDistances(
        plan: [SimilarPhotoComparison],
        features: [URL: FeatureBox]
    ) -> [SimilarPhotoPair] {
        var output: [SimilarPhotoPair] = []
        output.reserveCapacity(plan.count)

        for comparison in plan {
            if Task.isCancelled { break }

            guard let first = features[comparison.first.url]?.observation,
                  let second = features[comparison.second.url]?.observation
            else { continue }

            var distance: Float = 0
            do {
                try first.computeDistance(&distance, to: second)
                guard distance.isFinite else { continue }
                output.append(
                    SimilarPhotoPair(
                        first: comparison.first.url,
                        second: comparison.second.url,
                        distance: distance
                    )
                )
            } catch {
                continue
            }
        }

        return output
    }
}
