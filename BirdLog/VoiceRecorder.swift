import AVFoundation
import Foundation

enum VoiceRecorderError: LocalizedError {
    case permissionDenied, notRecording
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Microphone access is required for voice logging."
        case .notRecording: return "No voice recording is in progress."
        }
    }
}

@MainActor
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { throw VoiceRecorderError.permissionDenied }
        let url = FileManager.default.temporaryDirectory.appending(path: "birdlog-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        guard recorder.record() else { throw VoiceRecorderError.notRecording }
        fileURL = url
        self.recorder = recorder
    }

    func stop() -> Result<URL, Error> {
        guard let recorder, let fileURL else { return .failure(VoiceRecorderError.notRecording) }
        recorder.stop()
        self.recorder = nil
        self.fileURL = nil
        return .success(fileURL)
    }
}
