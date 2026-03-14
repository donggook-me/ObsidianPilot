import Foundation
import SwiftUI

@MainActor
class OrganizeViewModel: ObservableObject {
    @Published var selectedCategory: String = "auto"
    @Published var result: String = ""
    @Published var isRunning = false
    @Published var error: String?
    let progress = StreamProgress()

    // 후속 지시 관련
    @Published var followUpInput: String = ""
    @Published var followUpHistory: [FollowUpEntry] = []
    @Published var showFollowUp = false

    struct FollowUpEntry: Identifiable {
        let id = UUID()
        let instruction: String
        var result: String
        let timestamp: Date = Date()
    }

    /// 기본 카테고리 (항상 표시)
    static let fixedCategories: [(String, String, String)] = [
        ("auto", "자동 (최근 24시간)", "clock"),
        ("all", "전체 스캔", "globe"),
        ("root", "Root 정리", "folder"),
    ]

    /// vault에서 감지된 카테고리
    @Published var detectedCategories: [(String, String, String)] = []

    /// 고정 + 감지 카테고리
    var categories: [(String, String, String)] {
        var list = Self.fixedCategories
        list.insert(contentsOf: detectedCategories, at: 2) // all과 root 사이에 삽입
        return list
    }

    /// vault 폴더 구조에서 카테고리 로드
    func loadCategories(vault: VaultService) {
        let discovered = vault.discoverCategories()
        detectedCategories = discovered.map { cat in
            (cat.name, cat.name.capitalized, VaultCategoryInfo.iconFor(cat.name))
        }
    }

    func run(claude: ClaudeService, sessionStore: SessionStore) {
        guard !isRunning else { return }
        isRunning = true
        error = nil
        result = ""
        followUpHistory.removeAll()
        showFollowUp = false

        let category = selectedCategory == "auto" ? nil : selectedCategory
        let inputLabel = category ?? "auto (최근 24시간)"

        Task {
            do {
                let output = try await claude.organize(category: category, progress: progress)
                self.result = output
                // 결과에 미해결 항목이 있으면 후속 지시 패널 자동 표시
                if Self.hasUnresolvedItems(output) {
                    self.showFollowUp = true
                }
                sessionStore.add(Session(feature: "organize", input: inputLabel, result: output, durationSeconds: progress.elapsedSeconds))
            } catch is CancellationError {
                // cancelled
            } catch let err as ClaudeError where err.errorDescription == "작업이 취소되었습니다" {
                self.error = nil
            } catch {
                self.error = error.localizedDescription
                sessionStore.add(Session(feature: "organize", input: inputLabel, result: error.localizedDescription, isSuccess: false, durationSeconds: progress.elapsedSeconds))
            }
            self.isRunning = false
        }
    }

    func sendFollowUp(claude: ClaudeService, sessionStore: SessionStore) {
        let input = followUpInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isRunning else { return }

        let entry = FollowUpEntry(instruction: input, result: "")
        followUpHistory.append(entry)
        followUpInput = ""

        isRunning = true
        error = nil

        // 이전 결과 + 후속 지시 컨텍스트 구성
        let previousContext = result.count > 2000
            ? String(result.suffix(2000))
            : result

        let prompt = """
        [이전 Organize 작업 결과 요약]
        \(previousContext)

        [사용자 후속 지시]
        \(input)

        위 Organize 결과에서 미해결된 항목이나 사용자가 추가로 요청한 작업을 수행해줘.
        파일 이동, 이름 변경, 태그 추가, 링크 수정 등 필요한 작업을 직접 실행하고 결과를 알려줘.
        마크다운 형식으로 응답.
        """

        Task {
            do {
                let output = try await claude.runStreaming(prompt: prompt, progress: progress)
                // 마지막 entry 업데이트
                if let idx = self.followUpHistory.indices.last {
                    self.followUpHistory[idx].result = output
                }
                self.result = output // 최신 결과로 갱신
                sessionStore.add(Session(feature: "organize", input: "후속: \(input)", result: output, durationSeconds: progress.elapsedSeconds))
            } catch is CancellationError {
                // cancelled
            } catch let err as ClaudeError where err.errorDescription == "작업이 취소되었습니다" {
                self.error = nil
            } catch {
                self.error = error.localizedDescription
            }
            self.isRunning = false
        }
    }

    func cancel() {
        progress.cancel()
        isRunning = false
    }

    /// 결과에 미해결/확인 필요 항목이 있는지 감지
    private static func hasUnresolvedItems(_ text: String) -> Bool {
        let keywords = ["확인 필요", "결정 필요", "선택해", "어디로", "어떻게 처리",
                        "미분류", "판단이 필요", "수동으로", "직접 확인", "애매",
                        "질문", "의견", "검토", "TODO", "⚠️", "❓"]
        let lower = text.lowercased()
        return keywords.contains { lower.contains($0.lowercased()) }
    }
}
