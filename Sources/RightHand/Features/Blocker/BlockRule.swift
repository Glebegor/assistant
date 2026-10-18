import Foundation

/// One line of the block list. Supported forms:
/// - `instagram.com`            the whole site, including subdomains (www., m., …)
/// - `instagram`                any site named so: instagram.com, instagram.cz, …
/// - `*.example.com`            `*` matches anything
/// - `youtube.com/shorts`       only addresses that start with this (https:// and www. are ignored)
/// - `reddit.com/r/*/comments`  `*` inside the address matches anything
struct BlockRule: Hashable, Sendable {
    let text: String
    private let host: String
    /// nil = the whole site.
    private let path: String?

    init?(_ raw: String) {
        var rule = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !rule.isEmpty, !rule.hasPrefix("#") else { return nil }
        if let scheme = rule.range(of: "://") { rule = String(rule[scheme.upperBound...]) }
        if rule.hasPrefix("www.") { rule.removeFirst(4) }

        let parts = rule.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let host = String(parts[0])
        guard !host.isEmpty, !host.contains(" ") else { return nil }

        var path = parts.count > 1 ? "/" + parts[1] : ""
        // "shorts/*" and "shorts/" mean the same as "shorts": the page and everything under it.
        while path.hasSuffix("*") || path.hasSuffix("/") { path.removeLast() }

        self.text = raw.trimmingCharacters(in: .whitespaces)
        self.host = host
        self.path = path.isEmpty ? nil : path
    }

    /// Parses the block list (one rule per line), skipping empty and invalid lines.
    static func parse(_ text: String) -> [BlockRule] {
        text.split(whereSeparator: \.isNewline).compactMap { BlockRule(String($0)) }
    }

    func matches(_ url: URL) -> Bool {
        guard let urlHost = url.host()?.lowercased() else { return false }
        return hostMatches(urlHost) && pathMatches(url)
    }

    private func hostMatches(_ urlHost: String) -> Bool {
        if host.contains("*") { return Self.glob(host, matches: urlHost, prefixOnly: false) }
        if !host.contains(".") { return urlHost.split(separator: ".").contains { $0 == host } }
        return urlHost == host || urlHost.hasSuffix("." + host)
    }

    private func pathMatches(_ url: URL) -> Bool {
        guard let path else { return true }
        var target = url.path(percentEncoded: false).lowercased()
        if let query = url.query() { target += "?" + query.lowercased() }
        if path.contains("*") { return Self.glob(path, matches: target, prefixOnly: true) }
        if path.hasSuffix("?") || path.hasSuffix("=") { return target.hasPrefix(path) }
        return target == path || target.hasPrefix(path + "/") || target.hasPrefix(path + "?")
    }

    /// `*` matches any characters. With `prefixOnly` the pattern only has to match the start.
    private static func glob(_ pattern: String, matches value: String, prefixOnly: Bool) -> Bool {
        let regex = NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\*", with: ".*")
        return value.range(of: "^" + regex + (prefixOnly ? "" : "$"), options: .regularExpression) != nil
    }
}
