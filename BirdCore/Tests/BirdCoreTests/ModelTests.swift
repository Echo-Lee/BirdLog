import XCTest
@testable import BirdCore

final class ModelTests: XCTestCase {

    // MARK: - ObservationCount

    func testObservationCountEBirdValues() {
        XCTAssertEqual(ObservationCount.counted(2).eBirdValue, "2")
        XCTAssertEqual(ObservationCount.counted(25).eBirdValue, "25")
        XCTAssertEqual(ObservationCount.present.eBirdValue, "X")
    }

    func testObservationCountCodableRoundTrip() throws {
        func roundTrip(_ value: ObservationCount) throws -> ObservationCount {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(ObservationCount.self, from: data)
        }
        XCTAssertEqual(try roundTrip(.counted(7)), .counted(7))
        XCTAssertEqual(try roundTrip(.present), .present)
    }

    // MARK: - Observation

    func testNeedsReviewObservationCarriesSpokenTextAsSpecies() {
        let obs = Observation.needsReview(spokenText: "yellow rump warbler")
        XCTAssertEqual(obs.species.common, "yellow rump warbler")
        XCTAssertNil(obs.species.sci)
        XCTAssertNil(obs.species.aliases)
        XCTAssertTrue(obs.needsReview)
        XCTAssertEqual(obs.count, .present)   // no count spoken -> X
    }

    // MARK: - Species / Taxonomy

    func testTaxonomyDecodesGeneratorSchema() throws {
        // Exact shape produced by tools/make_taxonomy.py (no commonness — D4).
        let json = """
        [
          {"common": "American Robin", "sci": "Turdus migratorius", "aliases": ["robin"]},
          {"common": "Black-capped Chickadee", "sci": "Poecile atricapillus"}
        ]
        """
        let taxonomy = try Taxonomy(jsonData: Data(json.utf8))
        XCTAssertEqual(taxonomy.species.count, 2)
        XCTAssertEqual(taxonomy.species[0].aliases, ["robin"])
        XCTAssertNil(taxonomy.species[1].aliases)     // omitted -> nil
    }

    // MARK: - Checklist

    func testChecklistCapturesStartClockOnce() {
        let checklist = Checklist(startedAt: Date(timeIntervalSince1970: 1_000_000_000))
        XCTAssertTrue(checklist.startClock.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil)
        XCTAssertFalse(checklist.isComplete)
        XCTAssertNil(checklist.durationMinutes)
        XCTAssertEqual(checklist.distanceMiles, 0, accuracy: 0.0001)  // no end fix yet
    }

    func testChecklistDurationAndStraightLineDistance() {
        var checklist = Checklist(startedAt: Date(timeIntervalSince1970: 0),
                                  latitude: 0, longitude: 0)
        checklist.endedAt = Date(timeIntervalSince1970: 47 * 60)   // 47 minutes
        checklist.endLatitude = 0
        checklist.endLongitude = 1                                   // 1 degree of longitude

        XCTAssertEqual(checklist.durationMinutes, 47)
        // 1 degree of longitude at the equator = 6371 km * (pi/180) = 69.09 mi
        XCTAssertEqual(checklist.distanceMiles, 69.09, accuracy: 0.5)
        XCTAssertTrue(checklist.isComplete)
    }

    // MARK: - Persisted state round trip

    func testBirdLogStateJSONRoundTrip() throws {
        var checklist = Checklist(latitude: 42.8864, longitude: -78.8784)
        checklist.endLatitude = 42.9900
        checklist.endLongitude = -78.9000
        checklist.observations = [
            Observation(
                species: Species(common: "American Robin", sci: "Turdus migratorius",
                                  aliases: ["robin"]),
                count: .counted(2),
                comment: "singing from a spruce",
                spokenText: "robin two",
                timestamp: checklist.startedAt
            ),
            Observation.needsReview(spokenText: "a flock of geese",
                                    timestamp: checklist.startedAt),
        ]
        checklist.checklistComment = "Logged by voice with BirdLog (offline)"

        var state = BirdLogState(
            settings: EBirdSettings(stateCode: "NY", countryCode: "US", numberOfObservers: 1),
            activeChecklist: checklist
        )
        state.completedChecklists = [checklist]

        let decoded = try BirdLogState.from(jsonData: state.jsonData())

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.activeChecklist?.observations[0].count, .counted(2))
        XCTAssertEqual(decoded.activeChecklist?.observations[1].count, .present)
        XCTAssertEqual(decoded.activeChecklist?.observations[1].species.common, "a flock of geese")
        XCTAssertGreaterThan(decoded.activeChecklist?.distanceMiles ?? 0, 6)
    }
}
