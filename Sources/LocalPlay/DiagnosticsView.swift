import SwiftUI
import AppKit
import LocalPlayCore

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedLog: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 8) { Text("Diagnostics").font(.largeTitle.bold()); Text("Real execution logs. No estimated performance readings.").foregroundStyle(.secondary) }
                Spacer()
                Button("Export diagnostics…", systemImage: "square.and.arrow.up") { model.exportDiagnostics() }
            }
            HStack {
                StatCard(title: "AVERAGE FPS", value: "Unavailable", caption: "Measure in-game or with Metal HUD")
                StatCard(title: "FRAME TIMES", value: "Unavailable", caption: "No instrumentation attached")
                StatCard(title: "GAMEPLAY TEST", value: "Not verified", caption: "An install is not a gameplay test")
            }
            HStack {
                Text("Runtime output").font(.headline); Spacer()
                Button("Refresh logs", systemImage: "arrow.clockwise") { model.refreshLogs(); selectedLog = model.logFiles.first }
                Button("Reveal logs") { NSWorkspace.shared.open(model.paths.logs) }
            }
            if !model.logFiles.isEmpty {
                Picker("Log file", selection: $selectedLog) {
                    ForEach(model.logFiles, id: \.self) { Text($0.lastPathComponent).tag(Optional($0)) }
                }.labelsHidden()
                    .onChange(of: selectedLog) { _, file in if let file { model.logText = ProcessRunner.tail(file) } }
            }
            ScrollView([.vertical, .horizontal]) {
                Text(model.logText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(14)
            }.background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            Text("Raw Wine / Steam logs may contain personal information. The exported diagnostics uses a strict allowlist and excludes these logs, credentials, and account files.").font(.caption).foregroundStyle(.secondary)
        }.padding(28)
    }
}
