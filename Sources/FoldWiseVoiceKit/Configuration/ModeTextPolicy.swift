import Foundation

enum ModeTextPolicy {
    static func cleanName(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    static func cleanVocabulary(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = cleanName(value)
            guard !cleaned.isEmpty, seen.insert(comparisonKey(cleaned)).inserted else { continue }
            result.append(cleaned)
        }
        return result
    }

    static func comparisonKey(_ value: String) -> String {
        value.folding(
            options: .caseInsensitive,
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
