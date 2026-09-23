import Foundation
import XCTest

@testable import MacCleanKit

final class SimilarPhotoGroupingTests: XCTestCase {
    func testSupportedImageExtensionsAreCaseInsensitive() {
        XCTAssertTrue(SimilarPhotoGrouping.isSupportedImage(URL(fileURLWithPath: "/tmp/a.JPG")))
        XCTAssertTrue(SimilarPhotoGrouping.isSupportedImage(URL(fileURLWithPath: "/tmp/a.heic")))
        XCTAssertFalse(SimilarPhotoGrouping.isSupportedImage(URL(fileURLWithPath: "/tmp/a.mov")))
    }

    func testMetadataPrefilterAllowsResizedSameAspectRatio() {
        let a = asset("a.jpg", width: 4000, height: 3000)
        let b = asset("b.jpg", width: 1600, height: 1200)

        XCTAssertTrue(SimilarPhotoGrouping.shouldCompare(a, b))
    }

    func testMetadataPrefilterRejectsVeryDifferentAspectRatio() {
        let landscape = asset("landscape.jpg", width: 4000, height: 3000)
        let portrait = asset("portrait.jpg", width: 3000, height: 4000)

        XCTAssertFalse(SimilarPhotoGrouping.shouldCompare(landscape, portrait))
    }

    func testMetadataPrefilterRejectsExtremeResolutionGap() {
        let large = asset("large.jpg", width: 8000, height: 6000)
        let tiny = asset("tiny.jpg", width: 800, height: 600)

        XCTAssertFalse(SimilarPhotoGrouping.shouldCompare(large, tiny))
    }

    func testThresholdFiltersPairs() {
        let a = asset("a.jpg")
        let b = asset("b.jpg")
        let c = asset("c.jpg")

        let clusters = SimilarPhotoGrouping.clusters(
            assets: [a, b, c],
            pairs: [
                pair(a, b, 0.12),
                pair(a, c, 0.42),
            ],
            maximumDistance: 0.30
        )

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].anchor.url, a.url)
        XCTAssertEqual(clusters[0].members.map(\.asset.url), [b.url])
    }

    func testAnchorGroupingDoesNotCreateTransitiveBridge() {
        let a = asset("a.jpg")
        let b = asset("b.jpg")
        let c = asset("c.jpg")

        // A≈B and B≈C, but A-C has no qualifying edge. A connected-components
        // implementation would incorrectly create one 3-photo group.
        let clusters = SimilarPhotoGrouping.clusters(
            assets: [a, b, c],
            pairs: [
                pair(a, b, 0.10),
                pair(b, c, 0.11),
                pair(a, c, 0.80),
            ],
            maximumDistance: 0.30
        )

        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].count, 2)
        XCTAssertEqual(Set(clusters[0].allAssets.map(\.url)).count, 2)
    }

    func testEveryAssetAppearsInAtMostOneCluster() {
        let a = asset("a.jpg")
        let b = asset("b.jpg")
        let c = asset("c.jpg")
        let d = asset("d.jpg")

        let clusters = SimilarPhotoGrouping.clusters(
            assets: [a, b, c, d],
            pairs: [
                pair(a, b, 0.10),
                pair(a, c, 0.12),
                pair(b, d, 0.09),
                pair(c, d, 0.13),
            ],
            maximumDistance: 0.30
        )

        let urls = clusters.flatMap(\.allAssets).map(\.url)
        XCTAssertEqual(Set(urls).count, urls.count)
    }

    func testCloserLargerGroupsSortFirst() {
        let a = asset("a.jpg")
        let b = asset("b.jpg")
        let c = asset("c.jpg")
        let x = asset("x.jpg")
        let y = asset("y.jpg")

        let clusters = SimilarPhotoGrouping.clusters(
            assets: [a, b, c, x, y],
            pairs: [
                pair(a, b, 0.10),
                pair(a, c, 0.20),
                pair(x, y, 0.05),
            ],
            maximumDistance: 0.30
        )

        XCTAssertEqual(clusters.map(\.count), [3, 2])
    }

    func testComparisonPlanHonorsPerAssetAndGlobalCaps() {
        let assets = (0..<20).map { index in
            asset("p\(String(format: "%02d", index)).jpg")
        }

        let plan = SimilarPhotoGrouping.comparisonPlan(
            assets: assets,
            maxPartnersPerAsset: 3,
            maxTotalPairs: 17
        )

        XCTAssertLessThanOrEqual(plan.count, 17)

        let counts = Dictionary(grouping: plan, by: \.first.url)
            .mapValues(\.count)
        XCTAssertTrue(counts.values.allSatisfy { $0 <= 3 })
    }

    func testComparisonPlanIsDeterministic() {
        let assets = [
            asset("c.jpg"),
            asset("a.jpg"),
            asset("d.jpg"),
            asset("b.jpg"),
        ]

        let first = SimilarPhotoGrouping.comparisonPlan(
            assets: assets,
            maxPartnersPerAsset: 2,
            maxTotalPairs: 8
        )
        let second = SimilarPhotoGrouping.comparisonPlan(
            assets: assets.reversed(),
            maxPartnersPerAsset: 2,
            maxTotalPairs: 8
        )

        XCTAssertEqual(first, second)
    }

    private func asset(
        _ name: String,
        width: Int = 4000,
        height: Int = 3000
    ) -> SimilarPhotoAsset {
        SimilarPhotoAsset(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileSize: 1_000_000,
            pixelWidth: width,
            pixelHeight: height
        )
    }

    private func pair(
        _ a: SimilarPhotoAsset,
        _ b: SimilarPhotoAsset,
        _ distance: Float
    ) -> SimilarPhotoPair {
        SimilarPhotoPair(first: a.url, second: b.url, distance: distance)
    }
}
