import Foundation
import SwiftUI

/// 대화 메시지
struct IdeaMessage: Identifiable {
    let id = UUID()
    let role: Role
    var content: String
    let timestamp: Date = Date()

    enum Role {
        case user
        case assistant
        case context  // vault 컨텍스트 요약
    }
}

@MainActor
class IdeaViewModel: ObservableObject {
    @Published var result: String = ""
    @Published var isRunning = false
    @Published var error: String?
    @Published var lastFocus: String = "전체 분석"
    @Published var selectedFocus: String = "all"
    let progress = StreamProgress()

    // 대화형 인터페이스
    @Published var messages: [IdeaMessage] = []
    @Published var userInput: String = ""
    @Published var vaultContext: VaultContext?
    @Published var isLoadingContext = false
    @Published var selectedCategories: Set<String> = []

    /// Vault 컨텍스트 요약
    struct VaultContext {
        let categories: [VaultCategoryInfo]
        let recentFiles: [VaultFile]
        let totalFiles: Int
    }

    // MARK: - Vault 컨텍스트 로드

    func loadVaultContext(vault: VaultService) {
        isLoadingContext = true
        let allFiles = vault.allMarkdownFiles()
        let categories = vault.discoverCategories()

        vaultContext = VaultContext(
            categories: categories,
            recentFiles: Array(allFiles.prefix(10)),
            totalFiles: allFiles.count
        )

        // 처음 로드 시 모든 카테고리 선택
        if selectedCategories.isEmpty {
            selectedCategories = Set(categories.map { $0.name })
        }

        isLoadingContext = false
    }

    // MARK: - 대화형 아이디어 요청

    func sendMessage(claude: ClaudeService, vault: VaultService, sessionStore: SessionStore) {
        let input = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, !isRunning else { return }

        messages.append(IdeaMessage(role: .user, content: input))
        userInput = ""

        isRunning = true
        error = nil
        result = ""

        let categoryContext = selectedCategories.sorted().joined(separator: ", ")
        let conversationHistory = buildConversationContext()

        let prompt = """
        [컨텍스트]
        사용자의 Obsidian vault에서 다음 카테고리(폴더)를 참고하세요: \(categoryContext)
        vault 구조를 파악하고, 각 카테고리의 주요 노트와 MOC 파일을 확인한 후 응답해주세요.

        \(conversationHistory)
        [현재 요청]
        \(input)

        중요:
        - vault의 실제 파일과 내용을 읽어서 구체적으로 답변하세요
        - 새 노트 제안 시 제목, 위치, 내용 개요를 포함하세요
        - 기존 노트 간 연결점을 발견하면 [[wikilink]] 형태로 제안하세요
        - 마크다운 형식으로 응답하세요
        """

        Task {
            do {
                let output = try await claude.runStreaming(prompt: prompt, progress: progress)
                self.result = output
                self.messages.append(IdeaMessage(role: .assistant, content: output))
                sessionStore.add(Session(
                    feature: "ideas",
                    input: input,
                    result: output,
                    durationSeconds: progress.elapsedSeconds
                ))
            } catch is CancellationError {
                // cancelled
            } catch let err as ClaudeError where err.errorDescription == "작업이 취소되었습니다" {
                self.error = nil
            } catch {
                let errMsg = "\(error)"
                print("[IdeaVM] sendMessage error: \(errMsg)")
                self.error = errMsg
                self.messages.append(IdeaMessage(role: .assistant, content: "오류: \(errMsg)"))
            }
            self.isRunning = false
        }
    }

    // MARK: - 프리셋 실행

    func runPreset(_ preset: IdeaPreset, claude: ClaudeService, sessionStore: SessionStore) {
        guard !isRunning else { return }

        messages.append(IdeaMessage(role: .user, content: "[\(preset.label)] \(preset.description)"))
        userInput = ""
        isRunning = true
        error = nil
        result = ""
        lastFocus = preset.label

        Task {
            do {
                let output = try await claude.runStreaming(prompt: preset.prompt, progress: progress)
                self.result = output
                self.messages.append(IdeaMessage(role: .assistant, content: output))
                sessionStore.add(Session(
                    feature: "ideas",
                    input: preset.label,
                    result: output,
                    durationSeconds: progress.elapsedSeconds
                ))
            } catch is CancellationError {
                // cancelled
            } catch let err as ClaudeError where err.errorDescription == "작업이 취소되었습니다" {
                self.error = nil
            } catch {
                let errMsg = "\(error)"
                print("[IdeaVM] runPreset error: \(errMsg)")
                self.error = errMsg
                self.messages.append(IdeaMessage(role: .assistant, content: "오류: \(errMsg)"))
            }
            self.isRunning = false
        }
    }

    // MARK: - Legacy (메뉴바 호환)

    func suggest(claude: ClaudeService, sessionStore: SessionStore) {
        runPreset(.fullAnalysis, claude: claude, sessionStore: sessionStore)
    }

    func suggestFocused(focus: String, claude: ClaudeService, sessionStore: SessionStore) {
        guard let preset = IdeaPreset.fromFocus(focus) else { return }
        runPreset(preset, claude: claude, sessionStore: sessionStore)
    }

    func cancel() {
        progress.cancel()
        isRunning = false
    }

    func clearConversation() {
        messages.removeAll()
        result = ""
        error = nil
    }

    // MARK: - Private

    private func buildConversationContext() -> String {
        let recent = messages.suffix(6)
        guard !recent.isEmpty else { return "" }

        var lines: [String] = ["[이전 대화 맥락]"]
        for msg in recent {
            switch msg.role {
            case .user:
                lines.append("사용자: \(msg.content)")
            case .assistant:
                let trimmed = msg.content.count > 500
                    ? String(msg.content.prefix(500)) + "..."
                    : msg.content
                lines.append("어시스턴트: \(trimmed)")
            case .context:
                break
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - 프리셋 (범용)

enum IdeaPreset {
    case fullAnalysis
    case crossCategory
    case gaps
    case recentConnections

    var label: String {
        switch self {
        case .fullAnalysis: return "전체 분석"
        case .crossCategory: return "카테고리 간 연결"
        case .gaps: return "학습 갭 분석"
        case .recentConnections: return "최근 노트 연결"
        }
    }

    var description: String {
        switch self {
        case .fullAnalysis: return "전체 카테고리 간 연결점과 새 아이디어 분석"
        case .crossCategory: return "서로 다른 카테고리의 노트를 연결하는 아이디어"
        case .gaps: return "vault에서 부족한 영역과 탐구할 주제 발견"
        case .recentConnections: return "최근 수정된 노트와 기존 노트의 연결점"
        }
    }

    var icon: String {
        switch self {
        case .fullAnalysis: return "sparkles"
        case .crossCategory: return "link"
        case .gaps: return "magnifyingglass"
        case .recentConnections: return "clock.arrow.2.circlepath"
        }
    }

    var prompt: String {
        switch self {
        case .fullAnalysis:
            return """
            이 Obsidian vault의 전체 폴더 구조와 카테고리를 분석해서
            카테고리 간 연결점과 새로운 아이디어를 제안해줘.

            제안 유형:
            1. **카테고리 간 연결**: 서로 다른 폴더의 노트들이 어떻게 연결될 수 있는지
            2. **새 노트 제안**: 기존 노트들의 빈틈을 채울 수 있는 새 노트 아이디어
            3. **지식 연결**: 기존 노트의 인사이트가 다른 영역에 어떻게 적용되는지
            4. **학습 갭**: vault에서 부족한 영역이나 더 탐구하면 좋을 주제

            각 제안에 대해:
            - 제목
            - 연결되는 카테고리들
            - 구체적인 설명 (2-3문장)
            - 실행 방법 (어떤 노트를 작성하면 좋을지)

            중요: 비대화형 환경입니다. vault를 분석하고 결과를 바로 출력하세요.
            마크다운 형식으로 응답해줘.
            """

        case .crossCategory:
            return """
            이 Obsidian vault의 서로 다른 카테고리(폴더)에 있는 노트들을 분석해서,
            카테고리를 넘나드는 연결 노트(Bridge Note) 아이디어를 제안해줘.

            각 제안:
            - 제목
            - 연결되는 카테고리들과 구체적 노트
            - 어떤 개념이 어떻게 연결되는지
            - 새 노트를 어디에 만들면 좋을지

            vault의 실제 노트를 읽고 구체적으로 제안해줘.
            마크다운 형식으로 응답.
            """

        case .gaps:
            return """
            이 Obsidian vault를 분석해서, 현재 부족하거나 더 탐구하면 좋을 영역을 찾아줘.

            분석 항목:
            - 카테고리별 노트 밀도 비교
            - 다뤄지지 않은 하위 주제
            - 시작만 하고 깊이가 부족한 노트
            - 다른 카테고리에 비해 상대적으로 빈약한 영역

            각 발견에 대해 구체적인 학습/작성 방향을 제안해줘.
            마크다운 형식으로 응답.
            """

        case .recentConnections:
            return """
            이 Obsidian vault에서 최근 수정된 노트들을 확인하고,
            이 노트들이 기존 vault의 다른 노트들과 어떻게 연결될 수 있는지 분석해줘.

            분석 방법:
            1. 최근 7일 내 수정된 파일을 확인
            2. 각 파일의 내용과 관련된 기존 노트를 찾기
            3. [[wikilink]]로 연결할 수 있는 부분 제안
            4. 새로 작성하면 좋을 연결 노트 제안

            마크다운 형식으로 응답.
            """
        }
    }

    static func fromFocus(_ focus: String) -> IdeaPreset? {
        switch focus {
        case "all": return .fullAnalysis
        case "cross": return .crossCategory
        case "gaps": return .gaps
        case "recent": return .recentConnections
        default: return nil
        }
    }
}
