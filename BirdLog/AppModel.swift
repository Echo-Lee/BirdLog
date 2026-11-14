import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var health: BackendHealth?
    @Published private(set) var activeChecklist: RemoteChecklist?
    @Published private(set) var sightings: [RemoteSighting] = []
    @Published private(set) var status = "Checking the local model pipeline…"
    @Published private(set) var isWorking = false
    @Published private(set) var isRecording = false
    @Published var commandText = ""

    private let backend = BirdLogBackend()
    private let recorder = VoiceRecorder()

    init() { Task { await refreshHealth() } }

    func refreshHealth() async {
        do {
            health = try await backend.health()
            status = health?.bonsaiAvailable == true
                ? "Bonsai is ready. Tap the mic button and speak."
                : "Backend is reachable, but Bonsai is not loaded."
        } catch {
            health = nil
            status = "Start the local BirdLog backend on port 8000 to use voice commands."
        }
    }

    func toggleRecording() {
        if isRecording {
            let result = recorder.stop()
            isRecording = false
            guard case let .success(file) = result else { status = "Could not finish the recording."; return }
            Task { await submitVoiceFile(file) }
        } else {
            Task { await startRecording() }
        }
    }

    func sendTypedCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commandText = ""
        Task { await submitText(text) }
    }

    func startChecklist() { Task { await submitText("Start checklist at Beebe Lake") } }
    func addRobin() { Task { await submitText("Two American Robins") } }
    func endChecklist() { Task { await submitText("End checklist, logged with BirdLog") } }

    private func startRecording() async {
        do {
            try await recorder.start()
            isRecording = true
            status = "Listening… tap again when you finish speaking."
        } catch { status = error.localizedDescription }
    }

    private func submitVoiceFile(_ file: URL) async {
        isWorking = true
        status = "Argmax is transcribing your recording…"
        defer { isWorking = false; try? FileManager.default.removeItem(at: file) }
        do { apply(try await backend.submitVoice(file: file)) }
        catch { status = "Voice pipeline failed: \(error.localizedDescription)" }
    }

    private func submitText(_ text: String) async {
        isWorking = true
        status = "Sending \"\(text)\" to Bonsai…"
        defer { isWorking = false }
        do { apply(try await backend.submitText(text)) }
        catch { status = "Backend request failed: \(error.localizedDescription)" }
    }

    private func apply(_ result: PipelineResult) {
        activeChecklist = result.checklist
        sightings.append(contentsOf: result.rows)
        if let transcript = result.transcript {
            status = "Argmax heard: \"\(transcript)\" · parsed by \(result.parser)."
        } else if result.commands.contains("end_checklist") {
            status = "Checklist exported by the backend."
        } else if result.rows.isEmpty {
            status = "Command sent. No bird sightings were detected."
        } else {
            status = "Bonsai parsed \(result.rows.count) sighting(s)."
        }
    }
}
