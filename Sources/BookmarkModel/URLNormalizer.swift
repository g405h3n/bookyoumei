import Foundation

public struct URLNormalizer: Sendable {
    public static let defaultTrackingPatterns = ["utm_*", "fbclid", "gclid"]

    private let trackingMatchers: [TrackingMatcher]

    public init(trackingPatterns: [String] = URLNormalizer.defaultTrackingPatterns) {
        trackingMatchers = trackingPatterns.map(TrackingMatcher.init(pattern:))
    }

    public func storageNormalized(_ urlString: String) -> String {
        normalize(urlString, forComparison: false)
    }

    public func comparisonNormalized(_ urlString: String) -> String {
        normalize(urlString, forComparison: true)
    }

    private func normalize(_ urlString: String, forComparison: Bool) -> String {
        guard var components = URLComponents(string: urlString) else {
            return urlString
        }
        guard components.scheme != nil, components.host != nil else {
            return urlString
        }

        if let host = components.host {
            components.host = host.lowercased()
        }

        var path = components.percentEncodedPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path

        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { !isTrackingParameter($0.name) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        if forComparison, let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            components.scheme = "http"
        }

        return components.string ?? urlString
    }

    private func isTrackingParameter(_ name: String) -> Bool {
        trackingMatchers.contains { $0.matches(name: name) }
    }
}

private struct TrackingMatcher {
    private let lowercasedPattern: String

    init(pattern: String) {
        lowercasedPattern = pattern.lowercased()
    }

    func matches(name: String) -> Bool {
        let lowercasedName = name.lowercased()
        if lowercasedPattern.hasSuffix("*") {
            let prefix = String(lowercasedPattern.dropLast())
            return lowercasedName.hasPrefix(prefix)
        }
        return lowercasedName == lowercasedPattern
    }
}
