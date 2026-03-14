import Foundation
import SwiftUI

@MainActor
class CaptureViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var result: String = ""
    @Published var isRunning = false
    @Published var error: String?
    @Published var showResult = false
    let progress = StreamProgress()

    func capture(claude: ClaudeService, sessionStore: SessionStore) {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !isRunning else { return }
        isRunning = true
        error = nil
        result = ""

        let text = inputText
        let preview = String(text.prefix(50))

        Task {
            do {
                let output = try await claude.categorizeAndSave(text: text, progress: progress)
                self.result = output
                self.showResult = true
                self.inputText = ""
                sessionStore.add(Session(feature: "capture", input: preview, result: output, durationSeconds: progress.elapsedSeconds))
            } catch is CancellationError {
                // Task cancelled
            } catch let err as ClaudeError where err.errorDescription == "작업이 취소되었습니다" {
                self.error = nil
            } catch {
                self.error = error.localizedDescription
                sessionStore.add(Session(feature: "capture", input: preview, result: error.localizedDescription, isSuccess: false, durationSeconds: progress.elapsedSeconds))
            }
            self.isRunning = false
        }
    }

    func cancel() {
        progress.cancel()
        isRunning = false
    }
}
