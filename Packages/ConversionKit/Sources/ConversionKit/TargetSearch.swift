import Foundation

/// Type-to-filter for the Picker panel (SPEC §3): `pn` finds PNG.
public enum TargetSearch {

    /// The targets matching `query`, best matches first. A blank query keeps
    /// every target in its original order.
    public static func filter(_ targets: [FileFormat], query: String) -> [FileFormat] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return targets }

        // Lower is better; nil means no match. Ties keep catalog order.
        func rank(_ format: FileFormat) -> Int? {
            let names = [format.id, format.preferredExtension, format.displayName.lowercased()]
            if names.contains(query) { return 0 }
            if names.contains(where: { $0.hasPrefix(query) }) { return 1 }
            if format.displayName.lowercased().contains(query) { return 2 }
            return nil
        }

        let ranked: [(rank: Int, offset: Int, format: FileFormat)] = targets.enumerated()
            .compactMap { offset, format in
                guard let rank = rank(format) else { return nil }
                return (rank, offset, format)
            }
        return ranked.sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }.map(\.format)
    }
}
