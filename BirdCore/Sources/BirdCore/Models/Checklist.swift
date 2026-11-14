import Foundation

/// One checklist: one date, one location, one protocol, many observations.
///
/// Export constants (Step 6): EVERY checklist exports as Protocol "Traveling"
/// with All Obs Reported "Y" (what eBird calls a complete traveling checklist;
/// the template has no literal "Traveling - complete" value — completeness is
/// the separate Y/N row, per the sample file).
///
/// `startClock` ("HH:mm", 24-hour) is captured ONCE at start in the device's
/// then-current timezone, because eBird groups rows by start time and we must
/// not re-derive it at export (timezone/DST changes would corrupt it).
///
/// Distance is the straight line between the start fix and the end fix —
/// NOT accumulated. This keeps the app from holding the GPS radio open
/// for the whole drive (Step 7 requests one fix at start, one at end).
/// The exporter (Step 6) rounds it to 0.1 mi with a 0.1 mi minimum (D3).
public struct Checklist: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID

    public var startedAt: Date

    /// "HH:mm" frozen at checklist start.
    public var startClock: String

    /// IANA identifier of the zone `startClock` was captured in.
    public var timeZoneID: String

    /// Set by "end checklist" (Step 5). Nil while in progress.
    public var endedAt: Date?

    /// Start GPS fix. May arrive after `startedAt` and is filled in
    /// retroactively. Nil is fine for export (coords are optional per eBird).
    public var latitude: Double?
    public var longitude: Double?

    /// Fix captured when the checklist ends.
    public var endLatitude: Double?
    public var endLongitude: Double?

    public var observations: [Observation]

    /// Optional user-visible checklist note; the exporter (Step 6) combines
    /// this with per-species comments into the Notes row (D2) and appends
    /// "Logged by voice with BirdLog (offline)".
    public var checklistComment: String?

    public init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        latitude: Double? = nil,
        longitude: Double? = nil,
        checklistComment: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt

        let calendar = Calendar.current
        let comps = calendar.dateComponents([.hour, .minute], from: startedAt)
        self.startClock = String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        self.timeZoneID = calendar.timeZone.identifier

        self.endedAt = nil
        self.latitude = latitude
        self.longitude = longitude
        self.endLatitude = nil
        self.endLongitude = nil
        self.observations = []
        self.checklistComment = checklistComment
    }

    /// Whole minutes from start to end; nil while the checklist is open.
    public var durationMinutes: Int? {
        guard let endedAt else { return nil }
        let seconds = max(0, endedAt.timeIntervalSince(startedAt))
        return Int((seconds / 60.0).rounded())
    }

    /// Straight-line start->end distance in miles (haversine, Earth radius
    /// 6371 km). Zero until both fixes exist. Export applies the 0.1 mi floor.
    public var distanceMiles: Double {
        guard let lat0 = latitude, let lon0 = longitude,
              let lat1 = endLatitude, let lon1 = endLongitude else { return 0 }
        func radians(_ d: Double) -> Double { d * .pi / 180 }
        let dLat = radians(lat1 - lat0)
        let dLon = radians(lon1 - lon0)
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(radians(lat0)) * cos(radians(lat1)) * sin(dLon / 2) * sin(dLon / 2)
        let meters = 2 * 6_371_000.0 * atan2(sqrt(a), sqrt(1 - a))
        return meters / 1_609.344
    }

    public var isComplete: Bool {
        endedAt != nil
    }
}
