@testable import BookmarkModel
import Testing

@Suite("URLNormalizer")
struct URLNormalizerTests {
    @Test func storageNormalizationLowercasesHostStripsTrackingAndNormalizesTrailingSlash() {
        let normalizer = URLNormalizer()
        let input = "https://EXAMPLE.com/path/?utm_source=ads&fbclid=abc123&x=1&gclid=zzz"

        let output = normalizer.storageNormalized(input)

        #expect(output == "https://example.com/path?x=1")
    }

    @Test func storageNormalizationPreservesOriginalScheme() {
        let normalizer = URLNormalizer()

        let output = normalizer.storageNormalized("http://Example.com/path/")

        #expect(output == "http://example.com/path")
    }

    @Test func comparisonNormalizationTreatsHTTPAndHTTPSEquivalent() {
        let normalizer = URLNormalizer()
        let httpURL = "http://EXAMPLE.com/path/?utm_medium=email"
        let httpsURL = "https://example.com/path"

        let httpOutput = normalizer.comparisonNormalized(httpURL)
        let httpsOutput = normalizer.comparisonNormalized(httpsURL)

        #expect(httpOutput == "http://example.com/path")
        #expect(httpsOutput == "http://example.com/path")
    }

    @Test func trackingParametersAreConfigurable() {
        let normalizer = URLNormalizer(trackingPatterns: ["ref", "mc_*"])
        let input = "https://example.com/path/?ref=home&mc_cid=abc&utm_source=kept&x=1"

        let output = normalizer.storageNormalized(input)

        #expect(output == "https://example.com/path?utm_source=kept&x=1")
    }

    @Test func invalidURLFallsBackToOriginalString() {
        let normalizer = URLNormalizer()
        let input = "not a valid url"

        let output = normalizer.storageNormalized(input)

        #expect(output == input)
    }

    @Test func relativeURLFallsBackToOriginalString() {
        let normalizer = URLNormalizer()
        let input = "/path/?utm_source=ads&x=1"

        let output = normalizer.storageNormalized(input)

        #expect(output == input)
    }

    @Test func storageNormalizationPreservesEncodedPathSemantics() {
        let normalizer = URLNormalizer()
        let input = "https://example.com/a%2Fb/?utm_source=ads&x=1"

        let output = normalizer.storageNormalized(input)

        #expect(output == "https://example.com/a%2Fb?x=1")
    }
}
