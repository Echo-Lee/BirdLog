import Foundation

/// How many birds were seen. eBird's format allows a number or "x"
/// (present, not counted).
public enum ObservationCount: Codable, Hashable, Sendable {
    /// A real count, e.g. "two robins" -> .counted(2).
    case counted(Int)
    /// Present but not counted — the DEFAULT when no count is spoken
    /// ("robin", "a flock of geese"). Exports as X (D6).
    case present

    public var eBirdValue: String {
        switch self {
        case .counted(let n): return String(n)
        case .present: return "X"
        }
    }
}

/// One sighting inside a checklist.
///
/// `species` is NEVER optional — it always carries the name to export:
/// - Confident match: the taxonomy entry (e.g. "American Robin").
/// - Ambiguous/unmatched: a synthesized Species whose `common` is the spoken
///   text verbatim (e.g. "yellow rump warbler"), with `needsReview == true`.
///   The exporter writes that name as-is, so eBird's "Fix Species" step on
///   the import screen catches it instead of us guessing.
///
/// Merge rule (enforced by the engine in Step 5): if the same species is
/// spoken again with a number, `.present` upgrades to `.counted(n)` and any
/// existing count is replaced by the latest number.
public struct Observation: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID

    public var species: Species

    public var count: ObservationCount

    /// Free text spoken after a comma or the word "comment".
    /// The wide spreadsheet format has no per-species column, so these are
    /// folded into the checklist Notes row at export (D2, Step 6).
    public var comment: String?

    /// Verbatim spoken text, kept for "scratch that" confirmations and
    /// for re-matching if the same bird is mentioned again.
    public var spokenText: String

    public var needsReview: Bool

    public var timestamp: Date

    /// A sighting that could not be confidently matched. The exported
    /// common name IS the spoken text.
    public static func needsReview(spokenText: String, timestamp: Date = Date()) -> Observation {
        Observation(
            species: Species(common: spokenText),
            count: .present,
            spokenText: spokenText,
            needsReview: true,
            timestamp: timestamp
        )
    }

    public init(
        id: UUID = UUID(),
        species: Species,
        count: ObservationCount = .present,
        comment: String? = nil,
        spokenText: String,
        needsReview: Bool = false,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.species = species
        self.count = count
        self.comment = comment
        self.spokenText = spokenText
        self.needsReview = needsReview
        self.timestamp = timestamp
    }
}
