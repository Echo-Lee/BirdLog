// HTTP client for the BirdLog backend (FastAPI on localhost:8000).

import Foundation

struct Backend {
    let baseURL: URL

    init(_ url: String) {
        self.baseURL = URL(string: url.trimmingCharacters(in: CharacterSet(charactersIn: "/")))!
    }

    // MARK: - Endpoints

    /// GET /vocab?format=text — one bird species name per line.
    func fetchVocabulary() async throws -> [String] {
        guard let url = URL(string: baseURL.absoluteString + "/vocab?format=text") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    /// POST /sightings — the whole voice turn: transcript (+ GPS only when a
    /// checklist is being started).
    func post(transcript: String, latitude: Double?, longitude: Double?) async throws -> MessageResponse {
        var body: [String: Any] = ["transcript": transcript]
        if let lat = latitude, let lon = longitude {
            body["latitude"] = lat
            body["longitude"] = lon
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("sightings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(MessageResponse.self, from: data)
    }
}

// MARK: - Response model

struct MessageResponse: Decodable {
    struct Checklist: Decodable {
        let id: String
        let locationName: String
        let date: String
        let startTime: String
        let protocolField: String
        let rows: Int

        enum CodingKeys: String, CodingKey {
            case id
            case locationName = "location_name"
            case date
            case startTime = "start_time"
            case protocolField = "protocol"
            case rows
        }
    }

    struct Row: Decodable {
        let primaryComName: String
        let count: Int?
        let matchConfidence: Double?
        let matchScope: String?

        enum CodingKeys: String, CodingKey {
            case primaryComName = "primary_com_name"
            case count
            case matchConfidence = "match_confidence"
            case matchScope = "match_scope"
        }
    }

    let commands: [String]?
    let checklist: Checklist?
    let parser: String
    let sightingsFound: Int?
    let ebirdRowsWritten: Int?

    enum CodingKeys: String, CodingKey {
        case commands, checklist, parser, rows
        case sightingsFound = "sightings_found"
        case ebirdRowsWritten = "ebird_rows_written"
    }

    // rows is optional at the top level so `rows` doesn't have to be non-nil.
    let rows: [Row]?
}

extension MessageResponse {
    /// One-line summary for the terminal, e.g.:
    ///   START_CHECKLIST — Beebe Lake, 3 observers, Stationary
    ///   +3 sightings (Wood Duck, Sharp-shinned Hawk, ...)
    var summary: String {
        var parts: [String] = []
        if let commands = commands, !commands.isEmpty {
            parts.append(commands.joined(separator: "+").uppercased())
        }
        if let checklist = checklist {
            parts.append("OPEN: \(checklist.locationName) \(checklist.date) \(checklist.startTime) [\(checklist.rows) rows]")
        }
        if let names = rows?.map(\.primaryComName), !names.isEmpty {
            parts.append("+\(names.count) sighting(s): \(names.joined(separator: ", "))")
        }
        parts.append("parser=\(parser)")
        return parts.joined(separator: " — ")
    }
}