import Foundation

/// User-configurable export settings (defaults: NY / US, one observer).
/// State code must be 1-3 characters and country exactly 2 per the eBird
/// spreadsheet format; validation happens in the exporter (Step 6), which is
/// the single place that knows the format's rules.
public struct EBirdSettings: Codable, Hashable, Sendable {
    public var stateCode: String
    public var countryCode: String
    public var numberOfObservers: Int

    public init(
        stateCode: String = "NY",
        countryCode: String = "US",
        numberOfObservers: Int = 1
    ) {
        self.stateCode = stateCode
        self.countryCode = countryCode
        self.numberOfObservers = numberOfObservers
    }
}

/// The ENTIRE persisted app state, serialized as JSON by the app (Step 7)
/// whenever it mutates, and decoded on launch to survive an iOS kill.
/// Everything in here is value-typed and Sendable.
public struct BirdLogState: Codable, Hashable, Sendable {
    /// Bump and handle in a decoder wrapper if the shape ever changes.
    public var revision: Int

    public var settings: EBirdSettings

    /// Nil when no checklist is running.
    public var activeChecklist: Checklist?

    /// Closed checklists, oldest first. The exporter writes ALL of these into
    /// ONE spreadsheet-format file (D1).
    public var completedChecklists: [Checklist]

    public init(
        revision: Int = 1,
        settings: EBirdSettings = EBirdSettings(),
        activeChecklist: Checklist? = nil,
        completedChecklists: [Checklist] = []
    ) {
        self.revision = revision
        self.settings = settings
        self.activeChecklist = activeChecklist
        self.completedChecklists = completedChecklists
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func from(jsonData: Data) throws -> BirdLogState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BirdLogState.self, from: jsonData)
    }
}
