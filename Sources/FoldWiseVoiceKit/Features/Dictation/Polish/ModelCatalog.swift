// Curated guidance for common Ollama models, rated for this app's job:
// fast, faithful cleanup/rewriting of dictated text on Apple Silicon.

import Foundation

enum ModelCatalog {
    struct Entry: Identifiable {
        let name: String
        let fit: String
        let size: String
        let speed: Int // 1…5, higher = faster polish turnaround
        let quality: Int // 1…5, higher = better cleanup/rewrites
        let blurb: String
        var id: String {
            name
        }
    }

    static let entries: [Entry] = [
        Entry(
            name: "gemma3:1b", fit: "Simple cleanup", size: "815 MB", speed: 5, quality: 2,
            blurb: "The smallest download here. Quick punctuation and filler "
                + "cleanup on any Mac; too small for faithful Email rewrites."
        ),
        Entry(
            name: "llama3.2:1b", fit: "Simple cleanup", size: "1.3 GB", speed: 5, quality: 2,
            blurb: "Tiny and near-instant. Fine for punctuation and filler removal; "
                + "struggles with bigger rewrites like Email or Bullets."
        ),
        Entry(
            name: "llama3.2:3b", fit: "Everyday Modes", size: "2.0 GB", speed: 4, quality: 3,
            blurb: "Great balance for dictation. Fast enough to feel "
                + "instant and solid at following the mode prompts."
        ),
        Entry(
            name: "qwen2.5:3b", fit: "Multilingual Modes", size: "1.9 GB", speed: 4, quality: 3,
            blurb: "The default — sticks strictly to \"output only\" prompts, "
                + "with stronger multilingual dictation."
        ),
        Entry(
            name: "gemma2:2b", fit: "Simple cleanup", size: "1.6 GB", speed: 4, quality: 2,
            blurb: "Google's compact model. Snappy at simple cleanup; less strict "
                + "about \"output only the text\" prompts."
        ),
        Entry(
            name: "phi4-mini:3.8b", fit: "Multilingual Modes", size: "2.5 GB", speed: 4, quality: 3,
            blurb: "Microsoft's small model. Follows the mode prompts closely and "
                + "handles multilingual dictation well for its size."
        ),
        Entry(
            name: "gemma3:4b", fit: "Cleanup + rewrites", size: "3.3 GB", speed: 4, quality: 4,
            blurb: "Google's current small model — the best cleanup quality below "
                + "the 7B tier, with strong multilingual support."
        ),
        Entry(
            name: "qwen2.5:7b", fit: "Email + Bullets", size: "4.7 GB", speed: 3, quality: 4,
            blurb: "Noticeably better Email and Bullets rewrites. A beat slower; "
                + "comfortable on 16 GB+ Macs."
        ),
        Entry(
            name: "llama3.1:8b", fit: "High-quality rewrites", size: "4.9 GB", speed: 2, quality: 4,
            blurb: "High-quality rewriting and prompt adherence. Slower to respond; "
                + "wants ~8 GB of memory free."
        ),
        Entry(
            name: "mistral:7b", fit: "General-purpose Modes", size: "4.4 GB", speed: 3, quality: 3,
            blurb: "Solid all-rounder, but older instruction tuning than Qwen or "
                + "Llama at the same size."
        ),
    ]

    /// Exact match first, then match the family and size tier so
    /// "llama3.2:3b-instruct-q4_K_M" still gets guidance.
    static func entry(for name: String) -> Entry? {
        entries.first { $0.name == name }
            ?? entries.first { guidanceKey($0.name) == guidanceKey(name) }
            ?? entries.first { family($0.name) == family(name) }
    }

    private static func guidanceKey(_ name: String) -> String {
        let components = name.split(separator: ":", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return name }
        let family = components[0]
        let tag = components[1].split(separator: "-", maxSplits: 1).first.map(String.init) ?? ""
        return tag.contains(where: \.isNumber) ? "\(family):\(tag)" : family
    }

    private static func family(_ name: String) -> String {
        name.split(separator: ":", maxSplits: 1).first.map(String.init) ?? name
    }
}
