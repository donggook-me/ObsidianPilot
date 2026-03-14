import Foundation
import SwiftUI

@MainActor
class VerifyViewModel: ObservableObject {
    @Published var recentFiles: [VaultFile] = []
    @Published var selectedFile: VaultFile?
    @Published var result: String = ""
    @Published var isRunning = false
    @Published var error: String?
    let progress = StreamProgress()

    func loadRecentFiles(vault: VaultService) {
        recentFiles = vault.recentFiles(hours: 72)
    }

    func verify(claude: ClaudeService, sessionStore: SessionStore) {
        guard let file = selectedFile, !isRunning else { return }
        isRunning = true
        error = nil
        result = ""

        let fileName = file.displayName
        let filePath = file.relativePath

        Task {
            do {
                let output = try await claude.verify(filePath: filePath, progress: progress)
                self.result = output
                sessionStore.add(Session(feature: "verify", input: fileName, result: output, durationSeconds: progress.elapsedSeconds))
            } catch is CancellationError {
                // Task cancelled
            } catch let err as ClaudeError where err.errorDescription == "작업이 취소되었습니다" {
                self.error = nil
            } catch {
                self.error = error.localizedDescription
                sessionStore.add(Session(feature: "verify", input: fileName, result: error.localizedDescription, isSuccess: false, durationSeconds: progress.elapsedSeconds))
            }
            self.isRunning = false
        }
    }

    func cancel() {
        progress.cancel()
        isRunning = false
    }
}
