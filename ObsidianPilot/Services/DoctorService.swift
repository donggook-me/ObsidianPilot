import Foundation

// MARK: - Diagnostic Models

struct DoctorCheck: Identifiable, Codable {
    let id: String
    let name: String
    let category: String
    var status: CheckStatus
    var message: String
    var detail: String?
    var suggestion: String?

    enum CheckStatus: String, Codable {
        case pass
        case warning
        case fail
        case running
    }

    var icon: String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        }
    }
}

struct DoctorReport: Codable {
    let timestamp: Date
    let appVersion: String
    let osVersion: String
    let checks: [DoctorCheck]
    let environment: EnvironmentInfo
    let recentErrors: [ErrorEntry]

    struct EnvironmentInfo: Codable {
        let claudePath: String
        let claudeVersion: String
        let vaultPath: String
        let vaultFileCount: Int
        let baseSessionId: String?
        let isClaudeReady: Bool
    }

    struct ErrorEntry: Codable {
        let timestamp: Date
        let feature: String
        let input: String
        let error: String
    }

    var passCount: Int { checks.filter { $0.status == .pass }.count }
    var warningCount: Int { checks.filter { $0.status == .warning }.count }
    var failCount: Int { checks.filter { $0.status == .fail }.count }

    var overallStatus: DoctorCheck.CheckStatus {
        if failCount > 0 { return .fail }
        if warningCount > 0 { return .warning }
        return .pass
    }
}

// MARK: - Doctor Service

@MainActor
class DoctorService: ObservableObject {
    @Published var checks: [DoctorCheck] = []
    @Published var isRunning = false
    @Published var lastReport: DoctorReport?

    private let cacheDir: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ObsidianPilot", isDirectory: true)
        self.cacheDir = appDir.appendingPathComponent("doctor", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Run All Checks

    func runDiagnostics(claudePath: String, vaultPath: String, baseSessionId: String?, isClaudeReady: Bool, sessions: [Session]) async {
        isRunning = true
        checks = []

        // 1. Claude CLI 경로
        let cliCheck = checkClaudeCLI(path: claudePath)
        checks.append(cliCheck)

        // 2. Claude CLI 버전
        let versionCheck = await checkClaudeVersion(path: claudePath)
        checks.append(versionCheck)

        // 3. Vault 경로
        let vaultCheck = checkVaultPath(path: vaultPath)
        checks.append(vaultCheck)

        // 4. Vault 파일 접근
        let vaultFilesCheck = checkVaultFiles(path: vaultPath)
        checks.append(vaultFilesCheck)

        // 5. 세션 상태
        let sessionCheck = checkSessionState(baseSessionId: baseSessionId, isClaudeReady: isClaudeReady)
        checks.append(sessionCheck)

        // 6. Claude 응답 테스트
        let responseCheck = await checkClaudeResponse(claudePath: claudePath, vaultPath: vaultPath)
        checks.append(responseCheck)

        // 7. 최근 에러 패턴
        let errorCheck = checkRecentErrors(sessions: sessions)
        checks.append(errorCheck)

        // 8. 디스크 권한
        let permCheck = checkPermissions(vaultPath: vaultPath)
        checks.append(permCheck)

        // Report 생성 및 저장
        let claudeVersion = versionCheck.detail ?? ""
        let vaultFileCount = Int(vaultFilesCheck.detail ?? "0") ?? 0
        let recentErrors = sessions
            .filter { !$0.isSuccess }
            .prefix(10)
            .map { DoctorReport.ErrorEntry(
                timestamp: $0.timestamp,
                feature: $0.feature,
                input: String($0.input.prefix(100)),
                error: String($0.result.prefix(200))
            )}

        let report = DoctorReport(
            timestamp: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            checks: checks,
            environment: DoctorReport.EnvironmentInfo(
                claudePath: claudePath,
                claudeVersion: claudeVersion,
                vaultPath: vaultPath,
                vaultFileCount: vaultFileCount,
                baseSessionId: baseSessionId,
                isClaudeReady: isClaudeReady
            ),
            recentErrors: Array(recentErrors)
        )

        lastReport = report
        saveReport(report)
        isRunning = false
    }

    // MARK: - Individual Checks

    private func checkClaudeCLI(path: String) -> DoctorCheck {
        var check = DoctorCheck(
            id: "cli_path", name: "Claude CLI 경로", category: "CLI",
            status: .running, message: "확인 중..."
        )

        if path.isEmpty {
            check.status = .fail
            check.message = "Claude CLI 경로가 설정되지 않음"
            check.suggestion = "Settings에서 Claude CLI 경로를 설정하세요. 터미널에서 'which claude'로 경로를 확인할 수 있습니다."
            return check
        }

        if !FileManager.default.fileExists(atPath: path) {
            check.status = .fail
            check.message = "파일이 존재하지 않음: \(path)"
            check.suggestion = "Claude Code CLI를 설치하세요: npm install -g @anthropic-ai/claude-code"
            return check
        }

        if !FileManager.default.isExecutableFile(atPath: path) {
            check.status = .fail
            check.message = "실행 권한 없음: \(path)"
            check.suggestion = "chmod +x \(path) 를 실행하세요."
            return check
        }

        check.status = .pass
        check.message = path
        return check
    }

    private func checkClaudeVersion(path: String) async -> DoctorCheck {
        var check = DoctorCheck(
            id: "cli_version", name: "Claude CLI 버전", category: "CLI",
            status: .running, message: "확인 중..."
        )

        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            check.status = .fail
            check.message = "CLI를 실행할 수 없음"
            return check
        }

        do {
            let version = try await runShell(path, args: ["--version"], timeout: 10)
            if version.isEmpty {
                check.status = .warning
                check.message = "버전 정보를 가져올 수 없음"
            } else {
                check.status = .pass
                check.message = version.trimmingCharacters(in: .whitespacesAndNewlines)
                check.detail = check.message
            }
        } catch {
            check.status = .fail
            check.message = "CLI 실행 실패: \(error.localizedDescription)"
            check.suggestion = "Claude Code CLI가 정상 설치되었는지 확인하세요."
        }

        return check
    }

    private func checkVaultPath(path: String) -> DoctorCheck {
        var check = DoctorCheck(
            id: "vault_path", name: "Vault 경로", category: "Vault",
            status: .running, message: "확인 중..."
        )

        if path.isEmpty {
            check.status = .fail
            check.message = "Vault 경로가 설정되지 않음"
            check.suggestion = "Settings에서 Obsidian vault 경로를 설정하세요."
            return check
        }

        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            check.status = .fail
            check.message = "경로가 존재하지 않음: \(path)"
            return check
        }

        if !isDir.boolValue {
            check.status = .fail
            check.message = "디렉토리가 아님: \(path)"
            return check
        }

        let obsidianPath = (path as NSString).appendingPathComponent(".obsidian")
        if !FileManager.default.fileExists(atPath: obsidianPath) {
            check.status = .warning
            check.message = ".obsidian 폴더가 없음 (Obsidian vault가 아닐 수 있음)"
            check.suggestion = "Obsidian에서 이 폴더를 vault로 열어본 적이 있는지 확인하세요."
        } else {
            check.status = .pass
            check.message = path
        }

        return check
    }

    private func checkVaultFiles(path: String) -> DoctorCheck {
        var check = DoctorCheck(
            id: "vault_files", name: "Vault 파일", category: "Vault",
            status: .running, message: "확인 중..."
        )

        guard !path.isEmpty else {
            check.status = .fail
            check.message = "Vault 경로 없음"
            return check
        }

        do {
            let enumerator = FileManager.default.enumerator(atPath: path)
            var mdCount = 0
            while let file = enumerator?.nextObject() as? String {
                if file.hasSuffix(".md") { mdCount += 1 }
            }

            check.detail = "\(mdCount)"

            if mdCount == 0 {
                check.status = .warning
                check.message = "마크다운 파일이 없음"
                check.suggestion = "Vault에 .md 파일을 추가하세요."
            } else {
                check.status = .pass
                check.message = "\(mdCount)개 마크다운 파일 발견"
            }
        } catch {
            check.status = .fail
            check.message = "파일 목록을 읽을 수 없음"
        }

        return check
    }

    private func checkSessionState(baseSessionId: String?, isClaudeReady: Bool) -> DoctorCheck {
        var check = DoctorCheck(
            id: "session_state", name: "세션 상태", category: "세션",
            status: .running, message: "확인 중..."
        )

        if isClaudeReady, let sid = baseSessionId, !sid.isEmpty {
            check.status = .pass
            check.message = "활성 세션 있음 (fork 가능)"
            check.detail = String(sid.prefix(16)) + "..."
        } else if isClaudeReady {
            check.status = .warning
            check.message = "Claude 연결됨, 세션 ID 없음 (독립 모드)"
            check.suggestion = "앱을 재시작하면 세션이 생성됩니다."
        } else {
            check.status = .fail
            check.message = "Claude 미연결 (warm-up 실패)"
            check.suggestion = "Claude CLI가 정상 동작하는지 터미널에서 확인하세요: claude -p 'hello'"
        }

        return check
    }

    private func checkClaudeResponse(claudePath: String, vaultPath: String) async -> DoctorCheck {
        var check = DoctorCheck(
            id: "claude_response", name: "Claude 응답 테스트", category: "연결",
            status: .running, message: "테스트 중... (최대 30초)"
        )

        guard !claudePath.isEmpty, FileManager.default.isExecutableFile(atPath: claudePath) else {
            check.status = .fail
            check.message = "CLI를 실행할 수 없음"
            return check
        }

        do {
            let output = try await runShell(claudePath, args: [
                "-p", "--output-format", "text",
                "--no-session-persistence",
                "Reply with exactly: OK"
            ], timeout: 30, cwd: vaultPath)

            if output.lowercased().contains("ok") {
                check.status = .pass
                check.message = "Claude 정상 응답"
                check.detail = String(output.prefix(100))
            } else if output.isEmpty {
                check.status = .fail
                check.message = "빈 응답"
                check.suggestion = "Claude Pro/Max 구독이 활성화되어 있는지 확인하세요."
            } else {
                check.status = .warning
                check.message = "예상과 다른 응답"
                check.detail = String(output.prefix(200))
            }
        } catch {
            check.status = .fail
            check.message = "응답 실패: \(error.localizedDescription)"
            check.suggestion = "네트워크 연결과 Claude 구독 상태를 확인하세요."
        }

        return check
    }

    private func checkRecentErrors(sessions: [Session]) -> DoctorCheck {
        var check = DoctorCheck(
            id: "recent_errors", name: "최근 에러", category: "기록",
            status: .running, message: "확인 중..."
        )

        let recentSessions = sessions.prefix(20)
        let failures = recentSessions.filter { !$0.isSuccess }

        if failures.isEmpty {
            check.status = .pass
            check.message = "최근 20건 중 에러 없음"
        } else {
            let rate = Double(failures.count) / Double(recentSessions.count) * 100
            if rate > 50 {
                check.status = .fail
                check.message = "높은 에러율: \(failures.count)/\(recentSessions.count) (\(Int(rate))%)"
                // 가장 흔한 에러 패턴 분석
                let errorMessages = failures.compactMap { $0.result.isEmpty ? nil : String($0.result.prefix(80)) }
                if let common = mostCommon(errorMessages) {
                    check.detail = "주요 에러: \(common)"
                }
                check.suggestion = "반복되는 에러가 있다면 세션을 초기화하거나 앱을 재시작해보세요."
            } else {
                check.status = .warning
                check.message = "\(failures.count)/\(recentSessions.count)건 실패 (\(Int(rate))%)"
            }
        }

        return check
    }

    private func checkPermissions(vaultPath: String) -> DoctorCheck {
        var check = DoctorCheck(
            id: "permissions", name: "파일 권한", category: "시스템",
            status: .running, message: "확인 중..."
        )

        guard !vaultPath.isEmpty else {
            check.status = .fail
            check.message = "Vault 경로 없음"
            return check
        }

        let testFile = (vaultPath as NSString).appendingPathComponent(".obsidianpilot_permission_test")
        let testData = "test".data(using: .utf8)!

        do {
            try testData.write(to: URL(fileURLWithPath: testFile))
            try FileManager.default.removeItem(atPath: testFile)
            check.status = .pass
            check.message = "읽기/쓰기 권한 정상"
        } catch {
            check.status = .fail
            check.message = "Vault에 쓰기 권한 없음"
            check.suggestion = "시스템 설정 > 개인정보 보호 > 파일 및 폴더에서 앱 권한을 확인하세요."
        }

        return check
    }

    // MARK: - Issue Cache

    private func saveReport(_ report: DoctorReport) {
        let formatter = ISO8601DateFormatter()
        let filename = "report_\(formatter.string(from: report.timestamp)).json"
            .replacingOccurrences(of: ":", with: "-")
        let path = cacheDir.appendingPathComponent(filename)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            try data.write(to: path, options: .atomic)
            print("[Doctor] Report saved: \(path.lastPathComponent)")

            // 최근 10개만 유지
            cleanOldReports()
        } catch {
            print("[Doctor] Report save error: \(error)")
        }
    }

    private func cleanOldReports() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "json" }
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return da > db
                }
            for file in files.dropFirst(10) {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            // ignore
        }
    }

    /// 이전 리포트 목록
    func loadReportList() -> [(filename: String, date: Date)] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "json" }
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return da > db
                }
            return files.map { ($0.lastPathComponent, (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()) }
        } catch {
            return []
        }
    }

    /// 캐시 디렉토리 경로 (개발 에이전트용)
    var cachePath: String { cacheDir.path }

    // MARK: - Helpers

    private func runShell(_ executable: String, args: [String], timeout: TimeInterval, cwd: String? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args
                if let cwd = cwd, !cwd.isEmpty {
                    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
                }

                var env = ProcessInfo.processInfo.environment
                env.removeValue(forKey: "CLAUDECODE")
                env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
                process.environment = env

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Timeout
                let timer = DispatchSource.makeTimerSource(queue: .global())
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler {
                    if process.isRunning { process.terminate() }
                }
                timer.resume()

                process.waitUntilExit()
                timer.cancel()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: NSError(domain: "Doctor", code: -1, userInfo: [NSLocalizedDescriptionKey: "타임아웃 (\(Int(timeout))초)"]))
                } else {
                    continuation.resume(throwing: NSError(domain: "Doctor", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "종료 코드: \(process.terminationStatus)"]))
                }
            }
        }
    }

    private func mostCommon(_ items: [String]) -> String? {
        guard !items.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for item in items { counts[item, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
