import Foundation

struct BirdLogBackend {
    // For a physical phone, change this to the Mac's LAN IP address.
    private let baseURL = URL(string: "http://127.0.0.1:8000")!

    func health() async throws -> BackendHealth {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appending(path: "health"))
        try validate(response)
        return try JSONDecoder().decode(BackendHealth.self, from: data)
    }

    func submitText(_ transcript: String) async throws -> PipelineResult {
        var request = URLRequest(url: baseURL.appending(path: "sightings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["transcript": transcript])
        return try await send(request)
    }

    func submitVoice(file: URL) async throws -> PipelineResult {
        var request = URLRequest(url: baseURL.appending(path: "voice"))
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Data(contentsOf: file)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> PipelineResult {
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response)
        return try JSONDecoder().decode(PipelineResult.self, from: data)
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

struct BackendHealth: Decodable {
    let bonsaiAvailable: Bool
    enum CodingKeys: String, CodingKey { case bonsaiAvailable = "bonsai_available" }
}

struct PipelineResult: Decodable {
    let commands: [String]
    let checklist: RemoteChecklist?
    let parser: String
    let rows: [RemoteSighting]
    let transcript: String?
}

struct RemoteChecklist: Decodable, Hashable {
    let locationName: String
    let rows: Int
    enum CodingKeys: String, CodingKey { case locationName = "location_name"; case rows }
}

struct RemoteSighting: Decodable, Hashable {
    let primaryComName: String
    let count: Int?
    let parser: String
    let matchScope: String
    enum CodingKeys: String, CodingKey {
        case primaryComName = "primary_com_name"; case count, parser
        case matchScope = "match_scope"
    }
}
