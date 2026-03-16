import Foundation
import SwiftUI

// MARK: - Queue Item

@MainActor
class CaptureQueueItem: Identifiable, ObservableObject {
    let id = UUID()
    let text: String
    let preview: String
    let createdAt: Date = Date()
    @Published var status: CaptureStatus = .waiting
    @Published var result: String = ""
    @Published var error: String?
    let progress = StreamProgress()

    enum CaptureStatus: Equatable {
        case waiting
        case processing
        case completed
        case failed
    }

    init(text: String, preview: String) {
        self.text = text
        self.preview = preview
    }

    var statusIcon: String {
        switch status {
        case .waiting: return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var statusColor: Color {
        switch status {
        case .waiting: return .secondary
        case .processing: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

// MARK: - ViewModel

@MainActor
class CaptureViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var queue: [CaptureQueueItem] = []
    @Published var isProcessing = false
    @Published var showResult = false

    // 기존 호환
    var isRunning: Bool { isProcessing }
    var result: String { queue.last(where: { $0.status == .completed })?.result ?? "" }
    var error: String? { queue.last(where: { $0.status == .failed })?.error }
    var progress: StreamProgress { currentItem?.progress ?? StreamProgress() }

    private var processingTask: Task<Void, Never>?

    /// 큐에 추가하고 처리 시작
    func capture(claude: ClaudeService, sessionStore: SessionStore) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let preview = String(text.prefix(50))
        let item = CaptureQueueItem(text: text, preview: preview)
        queue.append(item)
        inputText = ""
        objectWillChange.send()

        if !isProcessing {
            processNext(claude: claude, sessionStore: sessionStore)
        }
    }

    private func processNext(claude: ClaudeService, sessionStore: SessionStore) {
        guard let item = queue.first(where: { $0.status == .waiting }) else {
            isProcessing = false
            return
        }

        isProcessing = true
        item.status = .processing
        objectWillChange.send()

        processingTask = Task {
            do {
                let output = try await claude.categorizeAndSave(text: item.text, progress: item.progress)
                item.status = .completed
                item.result = output
                showResult = true
                sessionStore.add(Session(
                    feature: "capture", input: item.preview, result: output,
                    durationSeconds: item.progress.elapsedSeconds
                ))
            } catch is CancellationError {
                item.status = .failed
                item.error = "취소됨"
            } catch let err as ClaudeError where err.errorDescription == "작업이 취소되었습니다" {
                item.status = .failed
                item.error = "취소됨"
            } catch {
                item.status = .failed
                item.error = error.localizedDescription
                sessionStore.add(Session(
                    feature: "capture", input: item.preview,
                    result: error.localizedDescription, isSuccess: false,
                    durationSeconds: item.progress.elapsedSeconds
                ))
            }

            objectWillChange.send()
            processNext(claude: claude, sessionStore: sessionStore)
        }
    }

    func cancel() {
        if let item = queue.first(where: { $0.status == .processing }) {
            item.progress.cancel()
            item.status = .failed
            item.error = "취소됨"
        }
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        objectWillChange.send()
    }

    func removeWaiting(_ itemId: UUID) {
        queue.removeAll { $0.id == itemId && $0.status == .waiting }
        objectWillChange.send()
    }

    func clearFinished() {
        queue.removeAll { $0.status == .completed || $0.status == .failed }
        objectWillChange.send()
    }

    var waitingCount: Int {
        queue.filter { $0.status == .waiting }.count
    }

    var currentItem: CaptureQueueItem? {
        queue.first { $0.status == .processing }
    }

    var hasQueueItems: Bool {
        !queue.isEmpty
    }
}
