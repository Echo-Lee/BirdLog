import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("Local model pipeline") {
                    Label(model.health?.bonsaiAvailable == true ? "Bonsai-2 ready" : "Bonsai-2 unavailable",
                          systemImage: model.health?.bonsaiAvailable == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.health?.bonsaiAvailable == true ? .green : .orange)
                    Text("Voice audio → Argmax transcription → Bonsai parse → eBird CSV")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Refresh model status") { Task { await model.refreshHealth() } }
                }

                Section("Voice input") {
                    Button(action: model.toggleRecording) {
                        Label(model.isRecording ? "Finish Recording" : "Record Birding Note",
                              systemImage: model.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    }
                    .tint(model.isRecording ? .red : .blue)
                    .disabled(model.isWorking)
                    Text(model.status).font(.footnote).foregroundStyle(.secondary)
                }

                Section("Typed fallback") {
                    TextField("e.g. Two wood ducks at Beebe Lake", text: $model.commandText)
                    Button("Send Command", action: model.sendTypedCommand)
                        .disabled(model.commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isWorking)
                    HStack {
                        Button("Start", action: model.startChecklist)
                        Spacer()
                        Button("Add Robin", action: model.addRobin)
                        Spacer()
                        Button("End", role: .destructive, action: model.endChecklist)
                    }
                    .disabled(model.isWorking)
                }

                if let checklist = model.activeChecklist {
                    Section("Active checklist") {
                        LabeledContent("Location", value: checklist.locationName)
                        LabeledContent("Export rows", value: "\(checklist.rows)")
                    }
                }

                Section("Parsed sightings") {
                    if model.sightings.isEmpty {
                        Text("No sightings parsed in this app session.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(model.sightings.enumerated()), id: \.offset) { _, sighting in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(sighting.primaryComName)
                                Text("\(sighting.parser) · \(sighting.matchScope)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(sighting.count.map(String.init) ?? "X").monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("BirdLog")
        }
    }
}

#Preview { ContentView().environmentObject(AppModel()) }
