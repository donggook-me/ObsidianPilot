import Foundation

/// Claude CLI 스트리밍 이벤트
struct StreamEvent {
    enum Kind: String {
        case thinking      // Claude가 생각 중
        case toolUse       // 도구 사용 시작
        case toolDetail    // 도구 상세 정보 (파일 경로 등)
        case toolResult    // 도구 결과
        case text          // 텍스트 응답 조각
        case result        // 최종 결과
        case error
    }

    let kind: Kind
    let message: String   // 사용자에게 보여줄 요약
    let detail: String    // 전체 내용
    var stepIcon: String = ""       // 단계 아이콘
    var stepLabel: String = ""      // 단계 라벨
}

/// 작업 단계
struct WorkStep: Identifiable {
    let id = UUID()
    let icon: String
    var label: String
    let timestamp: Date
    var isComplete: Bool = false
}

/// 스트리밍 진행 상황 추적
@MainActor
class StreamProgress: ObservableObject {
    @Published var events: [StreamEvent] = []
    @Published var currentActivity: String = "시작 중..."
    @Published var toolCallCount: Int = 0
    @Published var fileReadCount: Int = 0
    @Published var elapsedSeconds: Int = 0
    @Published var partialResult: String = ""
    @Published var steps: [WorkStep] = []
    @Published var phase: String = "준비"
    @Published var isCancelled: Bool = false
    @Published var isConnecting: Bool = true
    @Published var processedFiles: [String] = []
    /// CLI result JSON 원본 (사용량 정보 포함)
    @Published var resultJSON: String = ""

    private var timer: Timer?
    /// 현재 실행 중인 프로세스 (취소용)
    var currentProcess: Process?

    func start(isWarmSession: Bool = false) {
        events = []
        toolCallCount = 0
        fileReadCount = 0
        elapsedSeconds = 0
        partialResult = ""
        isCancelled = false
        isConnecting = true
        processedFiles = []
        currentProcess = nil

        if isWarmSession {
            currentActivity = "세션 재개 중..."
            steps = [WorkStep(icon: "⚡", label: "세션 재개 (캐시된 vault 컨텍스트)", timestamp: Date())]
            phase = "재개"
        } else {
            currentActivity = "Claude에 연결 중..."
            steps = [WorkStep(icon: "🔗", label: "Claude 연결", timestamp: Date())]
            phase = "연결"
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }

    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        currentProcess = nil
        currentActivity = "취소됨"
        if let lastIdx = steps.indices.last {
            steps[lastIdx].isComplete = true
        }
        steps.append(WorkStep(icon: "🚫", label: "사용자에 의해 취소됨", timestamp: Date(), isComplete: true))
        phase = "취소됨"
        stop()
    }

    func addEvent(_ event: StreamEvent) {
        events.append(event)
        currentActivity = event.message

        switch event.kind {
        case .toolUse:
            // 연결 완료 처리
            if isConnecting {
                isConnecting = false
                if let firstIdx = steps.indices.first {
                    steps[firstIdx].isComplete = true
                }
            }

            toolCallCount += 1
            let toolName = event.detail

            if toolName.contains("read") || toolName.contains("Read") {
                fileReadCount += 1
            }

            // 각 도구 호출마다 새 단계 추가 (개별 파일 추적)
            if let lastIdx = steps.indices.last {
                steps[lastIdx].isComplete = true
            }
            steps.append(WorkStep(
                icon: event.stepIcon.isEmpty ? "🔧" : event.stepIcon,
                label: event.stepLabel.isEmpty ? "처리 중" : event.stepLabel,
                timestamp: Date()
            ))
            phase = event.stepLabel

        case .toolDetail:
            // 최근 미완료 단계에 파일 경로 상세 추가
            if let lastIdx = steps.lastIndex(where: { !$0.isComplete }),
               !event.detail.isEmpty {
                let shortPath = shortenVaultPath(event.detail)
                steps[lastIdx].label += ": \(shortPath)"
                processedFiles.append(event.detail)
            }

        case .text:
            partialResult += event.detail
            if phase != "응답 작성" {
                if isConnecting {
                    isConnecting = false
                    if let firstIdx = steps.indices.first {
                        steps[firstIdx].isComplete = true
                    }
                }
                if let lastIdx = steps.indices.last {
                    steps[lastIdx].isComplete = true
                }
                steps.append(WorkStep(icon: "✍️", label: "응답 작성", timestamp: Date()))
                phase = "응답 작성"
            }

        case .result:
            if let lastIdx = steps.indices.last {
                steps[lastIdx].isComplete = true
            }
            steps.append(WorkStep(icon: "✅", label: "완료", timestamp: Date(), isComplete: true))
            phase = "완료"

        default:
            break
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var formattedTime: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return m > 0 ? "\(m)분 \(s)초" : "\(s)초"
    }

    /// 예상 진행률 (도구 호출 기반 휴리스틱)
    var estimatedProgress: Double {
        let estimated = max(Double(toolCallCount), 1.0)
        let typical = 15.0
        return min(estimated / typical, 0.95)
    }

    /// 연결 경고 메시지
    var connectionWarning: String? {
        guard isConnecting else { return nil }
        if elapsedSeconds > 30 {
            return "연결이 매우 오래 걸리고 있습니다. Claude CLI 상태를 확인하세요."
        } else if elapsedSeconds > 15 {
            return "연결이 평소보다 오래 걸리고 있습니다..."
        }
        return nil
    }

}

// MARK: - Path Utilities

/// 경로 단축 유틸리티 (actor-isolated가 아닌 자유 함수)
func shortenVaultPath(_ path: String) -> String {
    // vault 경로 이하만 표시 (마지막 2~3 경로 컴포넌트)
    let components = path.split(separator: "/")
    if components.count > 2 {
        return components.suffix(2).joined(separator: "/")
    }
    return path
}

// MARK: - Stream Parser (Claude CLI stream-json 포맷)

/// Claude CLI의 stream-json 출력을 파싱
class StreamParser {

    func parse(_ line: String) -> [StreamEvent] {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let type = json["type"] as? String ?? ""

        switch type {
        case "assistant":
            return parseAssistant(json)

        case "user":
            return parseToolResult(json)

        case "result":
            let resultText = json["result"] as? String ?? ""
            return [StreamEvent(kind: .result, message: "✅ 완료", detail: resultText)]

        case "error":
            let errorMsg = (json["error"] as? [String: Any])?["message"] as? String ?? "오류 발생"
            return [StreamEvent(kind: .error, message: "❌ \(errorMsg)", detail: errorMsg)]

        default:
            // system, rate_limit_event 등은 무시
            return []
        }
    }

    /// assistant 메시지의 content 배열을 파싱
    private func parseAssistant(_ json: [String: Any]) -> [StreamEvent] {
        guard let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else {
            return []
        }

        var events: [StreamEvent] = []

        for content in contentArray {
            let contentType = content["type"] as? String ?? ""

            switch contentType {
            case "thinking":
                // thinking 이벤트
                events.append(StreamEvent(kind: .thinking, message: "🧠 생각 중...", detail: ""))

            case "tool_use":
                // 도구 호출
                let toolName = content["name"] as? String ?? "도구"
                let input = content["input"] as? [String: Any] ?? [:]
                let (displayName, icon) = friendlyToolInfo(toolName)

                events.append(StreamEvent(
                    kind: .toolUse,
                    message: "\(icon) \(displayName)",
                    detail: toolName,
                    stepIcon: icon,
                    stepLabel: displayName
                ))

                // input에서 파일 경로나 커맨드 추출
                if let detailEvent = extractToolDetail(from: input, toolName: toolName) {
                    events.append(detailEvent)
                }

            case "text":
                // 텍스트 응답
                let text = content["text"] as? String ?? ""
                if !text.isEmpty {
                    events.append(StreamEvent(kind: .text, message: "✍️ 응답 작성 중...", detail: text))
                }

            default:
                break
            }
        }

        return events
    }

    /// user 메시지 (tool_result) 파싱
    private func parseToolResult(_ json: [String: Any]) -> [StreamEvent] {
        // tool_use_result에서 파일 정보 추출
        if let toolResult = json["tool_use_result"] as? [String: Any],
           let file = toolResult["file"] as? [String: Any],
           let filePath = file["filePath"] as? String {
            return [StreamEvent(
                kind: .toolDetail,
                message: "  → \(shortenVaultPath(filePath))",
                detail: filePath
            )]
        }

        // message.content에서 tool_result 확인
        if let message = json["message"] as? [String: Any],
           let contentArray = message["content"] as? [[String: Any]] {
            for content in contentArray {
                if content["type"] as? String == "tool_result" {
                    return [StreamEvent(kind: .toolResult, message: "도구 결과 수신", detail: "")]
                }
            }
        }

        return []
    }

    /// 도구 입력에서 파일 경로, 패턴, 커맨드 등 추출
    private func extractToolDetail(from input: [String: Any], toolName: String) -> StreamEvent? {
        // file_path
        if let fp = input["file_path"] as? String {
            return StreamEvent(kind: .toolDetail, message: "  → \(shortenVaultPath(fp))", detail: fp)
        }
        // path
        if let p = input["path"] as? String, (p.contains("/") || p.contains(".md")) {
            return StreamEvent(kind: .toolDetail, message: "  → \(shortenVaultPath(p))", detail: p)
        }
        // pattern (Glob/Grep)
        if let pat = input["pattern"] as? String {
            return StreamEvent(kind: .toolDetail, message: "  → \(pat)", detail: pat)
        }
        // command (Bash)
        if let cmd = input["command"] as? String {
            let short = String(cmd.prefix(60))
            return StreamEvent(kind: .toolDetail, message: "  → \(short)", detail: cmd)
        }
        return nil
    }

    private func friendlyToolInfo(_ name: String) -> (label: String, icon: String) {
        if name.contains("Read") || name.contains("read") { return ("파일 읽기", "📖") }
        if name.contains("Glob") || name.contains("glob") || name.contains("find") { return ("파일 검색", "🔍") }
        if name.contains("Grep") || name.contains("grep") || name.contains("search") { return ("내용 검색", "🔎") }
        if name.contains("Edit") || name.contains("edit") { return ("파일 수정", "✏️") }
        if name.contains("Write") || name.contains("write") || name.contains("create") { return ("파일 생성", "📝") }
        if name.contains("Bash") || name.contains("bash") || name.contains("shell") { return ("명령 실행", "⚡") }
        if name.contains("list_dir") || name.contains("ListDir") { return ("디렉토리 탐색", "📂") }
        if name.contains("replace") { return ("내용 교체", "✏️") }
        if name.contains("Agent") || name.contains("agent") { return ("에이전트 호출", "🤖") }
        return (name, "🔧")
    }
}

// MARK: - Claude Service

final class ClaudeService: Sendable {
    var vaultPath: String
    var claudePath: String

    /// Warm-up 세션 ID — vault 컨텍스트를 보유한 base 세션
    var baseSessionId: String?

    init(vaultPath: String, claudePath: String = "") {
        self.vaultPath = vaultPath
        self.claudePath = claudePath.isEmpty
            ? SettingsService.detectClaudePath()
            : claudePath
    }

    // MARK: - Session Warm-up

    /// 앱 시작 시 vault 구조를 사전 파악하는 경량 세션.
    /// 성공하면 baseSessionId가 설정되어 이후 작업이 이 세션에서 fork됨.
    func warmUp() async -> Bool {
        let sessionId = UUID().uuidString

        let prompt = """
        이 Obsidian vault의 구조를 파악해.
        최상위 폴더 목록을 확인하고, CLAUDE.md, README.md, HOME.md 등 안내 파일이 있으면 읽어.
        MOC(Map of Content) 파일이 있으면 구조를 파악해.
        한 줄로 요약 응답해.
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = URL(fileURLWithPath: vaultPath)
        process.arguments = [
            "-p",
            "--output-format", "text",
            "--session-id", sessionId,
            "--permission-mode", "default",
            prompt
        ]

        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return false
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                _ = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    self.baseSessionId = sessionId
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    // MARK: - CLI Argument Builder

    private func buildArguments(prompt: String, outputFormat: String, streaming: Bool) -> [String] {
        var args: [String] = []

        // base 세션이 있으면 fork하여 vault 컨텍스트 재활용
        if let sid = baseSessionId {
            args += ["--resume", sid, "--fork-session"]
        }

        args += ["-p", "--output-format", outputFormat]

        if streaming {
            args.append("--verbose")
        }

        args += ["--permission-mode", "acceptEdits"]

        // WebSearch, WebFetch 도구 허용
        args += ["--allowedTools", "WebSearch", "WebFetch"]

        // base 세션 없으면 기존 동작 (독립 실행)
        if baseSessionId == nil {
            args.append("--no-session-persistence")
        }

        args.append(prompt)
        return args
    }

    private func makeCleanEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        return env
    }

    // MARK: - Streaming CLI Runner

    func runStreaming(prompt: String, progress: StreamProgress) async throws -> String {
        let isWarm = baseSessionId != nil

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = URL(fileURLWithPath: vaultPath)
        process.arguments = buildArguments(prompt: prompt, outputFormat: "stream-json", streaming: true)
        process.environment = makeCleanEnv()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        await progress.start(isWarmSession: isWarm)
        await MainActor.run { progress.currentProcess = process }

        let fileHandle = stdout.fileHandleForReading

        let resultText: String = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var accumulated = ""
                var rawResultJSON = ""
                var buffer = Data()
                let parser = StreamParser()

                while true {
                    let chunk = fileHandle.availableData
                    if chunk.isEmpty { break }

                    buffer.append(chunk)

                    guard let text = String(data: buffer, encoding: .utf8) else { continue }
                    let lines = text.components(separatedBy: "\n")
                    buffer = lines.last.flatMap { $0.data(using: .utf8) } ?? Data()

                    for line in lines.dropLast() {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        // result 타입이면 원본 JSON 보존 (사용량 정보 포함)
                        if trimmed.contains("\"type\":\"result\"") {
                            rawResultJSON = trimmed
                        }

                        let events = parser.parse(trimmed)
                        for event in events {
                            Task { @MainActor in
                                progress.addEvent(event)
                                if event.kind == .result {
                                    accumulated = event.detail
                                }
                            }
                        }
                    }
                }

                // 남은 버퍼 처리
                if let remaining = String(data: buffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !remaining.isEmpty {
                    if remaining.contains("\"type\":\"result\"") {
                        rawResultJSON = remaining
                    }
                    let events = parser.parse(remaining)
                    for event in events {
                        Task { @MainActor in
                            progress.addEvent(event)
                            if event.kind == .result {
                                accumulated = event.detail
                            }
                        }
                    }
                }

                process.waitUntilExit()

                Task { @MainActor in
                    progress.resultJSON = rawResultJSON
                    progress.stop()
                }

                let exitCode = process.terminationStatus
                if process.terminationReason == .uncaughtSignal || exitCode == 15 || exitCode == 143 {
                    continuation.resume(throwing: ClaudeError.cancelled)
                    return
                }

                if exitCode != 0 {
                    // base 세션 fork 실패 시 세션 초기화
                    if self.baseSessionId != nil {
                        self.baseSessionId = nil
                    }
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: ClaudeError.processError(
                        code: exitCode, message: errorStr
                    ))
                } else {
                    let finalResult = accumulated.isEmpty ? "" : accumulated
                    continuation.resume(returning: finalResult)
                }
            }
        }

        let final = await progress.partialResult
        return resultText.isEmpty ? final : resultText
    }

    // MARK: - 기존 호환 run (스트리밍 없이)

    func run(prompt: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.currentDirectoryURL = URL(fileURLWithPath: vaultPath)
        process.arguments = buildArguments(prompt: prompt, outputFormat: "text", streaming: false)
        process.environment = makeCleanEnv()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            if baseSessionId != nil { baseSessionId = nil }
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ClaudeError.processError(code: process.terminationStatus, message: errorStr)
        }

        return String(data: outputData, encoding: .utf8) ?? ""
    }

    // MARK: - Feature Methods (스트리밍 지원)

    func organize(category: String? = nil, progress: StreamProgress? = nil) async throws -> String {
        let base = category != nil ? "/organize \(category!)" : "/organize"
        let prompt = """
        \(base)

        중요: 이 작업은 비대화형(non-interactive) 환경에서 실행됩니다.
        - 사용자에게 질문하거나 확인을 요청하지 마세요.
        - 판단이 어려운 경우 "수동 확인 필요" 섹션에 기록만 하세요.
        - 빈 파일(Untitled 등)은 삭제하지 말고 보고만 하세요.
        - frontmatter 필드 중 확신 없는 값은 비워두고 보고하세요.
        - 모든 작업을 자율적으로 수행한 후 결과를 마크다운으로 보고하세요.
        """
        if let progress = progress {
            return try await runStreaming(prompt: prompt, progress: progress)
        }
        return try await run(prompt: prompt)
    }

    func verify(filePath: String, progress: StreamProgress? = nil) async throws -> String {
        let prompt = """
        다음 Obsidian 파일의 내용을 검증해줘. 파일 경로: \(filePath)

        검증 항목:
        1. **사실 정확성**: 잘못된 정보나 오해가 있는지
        2. **논리 일관성**: 논리적 흐름이 자연스러운지, 모순은 없는지
        3. **빠진 맥락**: 추가하면 좋을 배경 정보나 맥락
        4. **탐구 제안**: 더 깊이 파고들 만한 주제나 연결점

        각 항목별로 구체적인 피드백을 제공해줘. 문제없는 항목은 "OK"로 표시.

        중요: 비대화형 환경입니다. 추가 질문 없이 파일을 읽고 검증 결과를 바로 출력하세요.
        마크다운 형식으로 응답해줘.
        """
        if let progress = progress {
            return try await runStreaming(prompt: prompt, progress: progress)
        }
        return try await run(prompt: prompt)
    }

    func suggestIdeas(progress: StreamProgress? = nil) async throws -> String {
        let prompt = """
        이 Obsidian vault의 전체 폴더 구조와 카테고리를 분석해서
        카테고리 간 연결점과 새로운 아이디어를 제안해줘.

        제안 유형:
        1. **카테고리 간 연결**: 서로 다른 카테고리의 노트들이 어떻게 연결될 수 있는지
        2. **새 노트 제안**: 기존 노트들의 빈틈을 채울 수 있는 새 노트 아이디어
        3. **지식 연결**: 기존 노트의 인사이트가 다른 영역에 어떻게 적용되는지
        4. **학습 갭**: vault에서 부족한 영역이나 더 탐구하면 좋을 주제

        각 제안에 대해:
        - 제목
        - 연결되는 카테고리들
        - 구체적인 설명 (2-3문장)
        - 실행 방법 (어떤 노트를 작성하면 좋을지)

        중요: 비대화형 환경입니다. 추가 질문 없이 vault를 분석하고 결과를 바로 출력하세요.
        마크다운 형식으로 응답해줘.
        """
        if let progress = progress {
            return try await runStreaming(prompt: prompt, progress: progress)
        }
        return try await run(prompt: prompt)
    }

    func categorizeAndSave(text: String, progress: StreamProgress? = nil) async throws -> String {
        let prompt = """
        다음 텍스트를 분석해서 이 Obsidian vault에 적절히 저장해줘.

        텍스트:
        \(text)

        규칙:
        1. vault의 기존 폴더 구조를 확인하고, 내용에 맞는 카테고리(폴더)를 판단
        2. 해당 카테고리의 기존 파일 네이밍 패턴에 맞는 파일명 생성
        3. 올바른 frontmatter 추가
        4. 적절한 폴더에 파일 생성
        5. 필요하면 관련 MOC에 백링크 추가

        중요: 비대화형 환경입니다. 카테고리 판단이 어려우면 내용의 핵심 키워드를 기반으로 최선의 판단을 내리세요.
        추가 질문 없이 파일을 생성하고, 어떤 파일을 어디에 생성했는지 결과를 마크다운으로 알려줘.
        """
        if let progress = progress {
            return try await runStreaming(prompt: prompt, progress: progress)
        }
        return try await run(prompt: prompt)
    }
}

enum ClaudeError: LocalizedError {
    case processError(code: Int32, message: String)
    case noOutput
    case cancelled

    var errorDescription: String? {
        switch self {
        case .processError(let code, let message):
            return "Claude 프로세스 오류 (코드: \(code)): \(message)"
        case .noOutput:
            return "Claude로부터 응답이 없습니다"
        case .cancelled:
            return "작업이 취소되었습니다"
        }
    }
}
