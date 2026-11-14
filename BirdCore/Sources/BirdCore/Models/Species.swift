import Foundation

/// One row of the bundled eBird taxonomy.
///
/// Codable keys match the generator's schema exactly (tools/make_taxonomy.py):
/// `{"common": String, "sci": String?, "aliases": [String]?}`
///
/// Decision D4: there is deliberately NO commonness/weight field. The matcher
/// (Step 4) breaks ties by edit distance and marks ambiguous exact hits
/// needsReview instead; shorthand support comes from aliases.
public struct Species: Codable, Hashable, Sendable {
    /// eBird common name, e.g. "American Robin".
    public let common: String

    /// Scientific name, e.g. "Turdus migratorius". Nil if absent in the source.
    public let sci: String?

    /// Extra spoken shorthands, e.g. ["robin"]. Stored lowercase from the
    /// generator; the matcher normalizes again at compare time.
    public let aliases: [String]?

    public init(common: String, sci: String? = nil, aliases: [String]? = nil) {
        self.common = common
        self.sci = sci
        self.aliases = aliases
    }
}

/// The loaded taxonomy. Pure data; all matching logic lives in Step 4.
public struct Taxonomy: Sendable {
    public let species: [Species]

    public init(species: [Species]) {
        self.species = species
    }

    /// Decode the bundled taxonomy.json (or any JSON with the same shape).
    public init(jsonData: Data) throws {
        self.species = try JSONDecoder().decode([Species].self, from: jsonData)
    }
}
